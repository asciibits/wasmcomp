(module
  ;; DEBUG_START
  (func $logZoomStart (import "test" "zoomStart") (param i32 i32))
  (func $logZoomEnd (import "test" "zoomEnd") (param i32 i32 i32 i32))
  ;; DEBUG_END

  (func $min (param i32 i32) (result i32)
    (select
      (local.get 0)
      (local.get 1)
      (i32.le_u (local.get 0) (local.get 1))
    )
  )
  (func $max (param i32 i32) (result i32)
    (select
      (local.get 0)
      (local.get 1)
      (i32.ge_u (local.get 0) (local.get 1))
    )
  )

  (func (export "encode_bit")
    (param $low i32)
    (param $high i32)
    (param $scratch i64)
    (param $bit_pos i32)
    (param $p_num i32)
    (param $p_den i32)
    (param $bit i32)

    ;; the new low
    (result i32)
    ;; the new high
    (result i32)
    ;; the new scratch
    (result i64)
    ;; the new bit_pos
    (result i32)

    (local $mid i32)

    ;; mid = (p_num * (high - low - 1) + p_den / 2) / p_den + low
    ;; mid = min(mid, high - (p_num != p_den))
    ;; mid = max(mid, low + (p_num != 0))
    (local.set $mid
      (call $max
        (call $min
          (i32.add
            (i32.wrap_i64
              (i64.div_u
                (i64.add
                  (i64.mul
                    (i64.extend_i32_u (local.get $p_num))
                    (i64.extend_i32_u (i32.sub (i32.sub (local.get $high) (local.get $low)) (i32.const 1)))
                  )
                  (i64.extend_i32_u (i32.shr_u (local.get $p_den) (i32.const 1)))
                )
                (i64.extend_i32_u (local.get $p_den))
              )
            )
            (local.get $low)
          )
          (i32.sub (local.get $high) (i32.ne (local.get $p_num) (local.get $p_den)))
        )
        (i32.add (local.get $low) (i32.ne (local.get $p_num) (i32.const 0)))
      )
    )

    (i32.const 0)
    (i32.const 0)
    (i64.const 0)
    (i32.const 0)
  )

  ;; Zoom into the window until we can no longer zoom into the high 16 bit
  ;; region, nor the low 16 bit region, nor the middle 16 bit region.
  ;;
  ;; When zooming in, the idea is to keep doubling the gap between low and high
  ;; until there's no more room within the scope of an i32. The trick is to
  ;; zoom in a way to make resolving the high/low bits managable.
  ;; This implementation was inspired (and heavily assisted) by the guide at
  ;; https://marknelson.us/posts/2014/10/19/data-compression-with-arithmetic-coding.html
  ;;
  ;; Below, we use the values:
  ;;   MAX =           2^32 (Not actually used - outside range of i32)
  ;;   THREE_QUARTER = 0xC0000000 = 0b110..0  // 32 bits
  ;;   HALF =          0x80000000 = 0b100..0  // 32 bits
  ;;   QUARTER =       0x40000000 = 0b010..0  // 32 bits
  ;;   ZERO =          0x00000000 = 0b000..0  // 32 bits
  ;;
  ;; * If both low and high are >= HALF: double their distance below 2^32;
  ;;   emit a '1' bit to indicate "zoom high". Ex: the value THREE_QUARTER
  ;;   would become HALF. The algorithm is: x -> (x-HALF)*2
  ;;
  ;; * If both low and high are < HALF: double their distance above 0; emit a
  ;;   '0' bit to indicate "zoom low". Ex: the value QUARTER would become HALF.
  ;;    The algorithm is: x -> x*2
  ;;
  ;; * If low >= QUARTER and high <= THREE_QUARTER: double their distance from
  ;;   HALF. The algorithm is: x -> (x-QUARTER)*2
  ;;   Don't emit a bit yet - we only emit bits when zooming high or low.
  ;;   Instead, keep a tally of these consecutive "zoom mid"s, and eventually
  ;;   resolve them into a sequence of zoom high/low as follows:
  ;;   If the first zoom after a series of zoom-mids is a zoom high, this
  ;;   resolves to a single '1' bit followed by enough '0's to account for all
  ;;   the zooms. If instead the first zoom aafter the mid-zooms is a low, this
  ;;   resolves to a single '0' bit followed by a string of '1's.
  ;;
  ;; In all cases above, the zoom logic keeps the low and high bounds within
  ;; the scope of an i32. When all zooming is done, the distance between high
  ;; and low is guaranteed to be greater than QUARTER, and as high as MAX.
  ;;
  ;; Also note: Given any starting low/high range, the serier of zooms will
  ;; always start with 0 or more low/high zooms, followed by 0 or more
  ;; mid-zooms. But, once a mid-zoom happens, any remaining zooms will also be
  ;; "mid". This is because during a mid-zoom the high and low will contionue
  ;; to straddle the HALF point preventing either high<=HALF or low>=HALF.
  ;;
  ;; Also note: the max number of zooms is 31, and that can only happen if the
  ;; very last zoom just happens to perfectly max out the entire range
  ;; (low = 0, high = 2^32-1)
  ;;
  ;; Now for the optimized algorithm:
  ;;
  ;; First, note that a "zoom high" emits a '1', and undergoes a "(x-HALF)*2"
  ;; The bit-pattern starts as: 0b1xx..xxx. The high bit is a '1' since it is
  ;; >= HALF. Subtracting HALF effectively clears that high bit, and the "*2"
  ;; shifts the remainder to the left leaving: 0bxx..xxx0. Which can be viewed
  ;; as "left shift, emit the bit falling off the left"
  ;;
  ;; Zoom lows are similar, except the high bit is a 0: 0b0yy..yyy. It is
  ;; similarly shifted, this time emiting a '0', leaving: 0byy...yyy0. Again,
  ;; it is "left shift, emit the bit falling off the left"
  ;;
  ;; And lastly, zoom mids work on values whose high bits are either 01 or 10
  ;; (Given the condition: QUARTER <= x < THREE_QUARTER)
  ;; The algorithm "(x-QUARTER)*2" first subtracts that QUARTER. Which changes
  ;; the high bits as: 01 -> 00, 10 -> 01. I.e. the high bit becomes '0', and
  ;; the 2nd high bit is flipped. Then it is bit shifted as above.
  ;;
  ;; Note that a high zoom is only possible when both low and (high-1) values
  ;; have a high bit of 1. Similarly, a low zoom only happens when both
  ;; have a high bit of 0. To find the set of initial high/low zooms, we just
  ;; see how many high order bits both high and low have in common. Those
  ;; become the "emitted bits".
  ;;
  ;; After that initial set of matching high order bits, the next bit of low
  ;; and high will necessarily be different. A "mid zoom" is possible if the
  ;; following bit of high is a 0, and the following bit of low is a 1. And
  ;; this continues, as long as high has another 0 bit, and low has another 1
  ;; bit, we continue to have a "zoom mid"
  ;;
  ;; For example, consider the example:
  ;;
  ;; high = 0b101000..00 // 32 bits, .. = 0s
  ;; low =  0b100110..00 // 32 bits, .. = 0s
  ;;
  ;; These have a matching set of high bits: '10', indicating a high then low
  ;; zoom. Next, we have a '100' in the high, and a '011' in the low. That
  ;; indicates 2 mid-zooms (Not 3, but 2 - 1 less than the pattern length)
  ;;
  ;; So, we have 2 "normal" bits, 2 "trailing mid zooms", and a resulting
  ;; low/high as:
  ;;
  ;; high = 0b10..00 // 32 bits
  ;; low =  0b00..00 // 32 bits
  ;;
  ;; That is, each value left shifted 4 times (2 for the high/low, 2 for the
  ;; mid), and because there were >0 mids, the new high bit is flipped.
  (func $_zoom (export "_zoom")
    ;; Initial condition:
    ;;   0 <= low < mid < high <= 2^32 (where 2^32 is represented as 0)
    ;; Where "mid" is some i32 value that is between low and high (exclusively)
    ;;
    ;; Said another way: low < high-1
    ;;
    ;; The lower bound (inclusive). Between 0 and 2^32-2
    (param $low i32)
    ;; The upper bound (exclusive). Between 2 and 2^32 (note: 2^32 will be = 0)
    (param $high i32)

    ;; the new low after all the zooms
    (result i32)
    ;; the new high after all the zooms
    (result i32)
    ;; the # of initial low/high zooms before any trailing mid-zooms
    (result i32)
    ;; the # of mid-zooms after the initial low/high zooms
    (result i32)

    (local $high_incl i32)
    (local $high_match_count i32)
    (local $mask i32)
    (local $zoom_count i32)
    (local $flip_high i32)

    ;; DEBUG_START
    (local $dbg1 i32)
    (local $dbg2 i32)
    (local $dbg3 i32)
    (local $dbg4 i32)

    (call $logZoomStart (local.get $low) (local.get $high))
    ;; DEBUG_END

    ;; Many parts of this algorithm use the inclusive value of $high
    (local.set $high_incl (i32.sub (local.get $high) (i32.const 1)))

    ;; low_mask = 0b011..11 >>> high_match_count; a mask to remove the
    ;; matching bits, plus the first non-matching bit
    (local.set $mask
      (i32.shr_u
        (i32.const 0x7FFFFFFF)
        ;; high_match_count = clz(comp_bits) ;; i.e. # of leading zeros
        (local.tee $high_match_count
          (i32.clz
            ;; comp_bits = low ^ high
            (i32.xor (local.get $low) (local.get $high_incl))
          )
        )
      )
    )

    ;; zoom_count = min(clz(high & mask), clz(~low & mask)) - 1
    ;; i.e. find the # of bits where high = 0 and low = 1 after the initial
    ;; set
    (local.set $zoom_count
      (i32.sub 
        (call $min
          (i32.clz
            (i32.and (i32.xor (local.get $low) (i32.const -1)) (local.get $mask))
          )
          (i32.clz (i32.and (local.get $high_incl) (local.get $mask)))
        )
        (i32.const 1)
      )
    )

    ;; flip_high = 0b100..00 * (zoom_count > high_match_count)
    ;; i.e. a mask for the high bit if there are any mid zooms
    (local.set $flip_high
      (i32.mul
        (i32.const 0x80000000)
        (i32.gt_u (local.get $zoom_count) (local.get $high_match_count))
      )
    )

    ;; result: low = (low << zoom_count) ^ flip_high
    (i32.xor
      (i32.shl (local.get $low) (local.get $zoom_count))
      (local.get $flip_high)
    )
    ;; result: high = (high << zoom_count) ^ flip_high | (1 << zoom_count - 1)
    (i32.xor
      (i32.shl (local.get $high) (local.get $zoom_count))
      (local.get $flip_high)
    )
    ;; result: standard zooms
    (local.get $high_match_count)
    ;; result: mid zooms
    (i32.sub (local.get $zoom_count) (local.get $high_match_count))

    ;; DEBUG_START
    (local.set $dbg4)
    (local.set $dbg3)
    (local.set $dbg2)
    (local.set $dbg1)
    (call $logZoomEnd (local.get $dbg1) (local.get $dbg2) (local.get $dbg3) (local.get $dbg4))
    (local.get $dbg1)
    (local.get $dbg2)
    (local.get $dbg3)
    (local.get $dbg4)
    ;; DEBUG_END
  )
)
