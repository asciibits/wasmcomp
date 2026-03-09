import {readFile} from 'node:fs/promises';
import {loadWebAric, WebAric} from '../src/webaric.js';
import {suite, test, before, beforeEach} from 'node:test';
import {strict as assert} from 'node:assert/strict';

let webaric: WebAric;
let enableLogging = false;

function getLoggerFor(text: string) {
  return (...values: number[]) => {
    if (enableLogging) {
      console.log(
        text,
        values.map(v => (v >>> 0).toString(2).padStart(32, '0')),
      );
    }
  };
}

before(async () => {
  webaric = await loadWebAric(await readFile('./lib/webaric.wasm'), {
    zoomStart: getLoggerFor('zoomStart'),
    zoomEnd: getLoggerFor('zoomEnd'),
  });
});

beforeEach(() => {
  enableLogging = false;
});

suite('Arithmetic Coder', () => {
  suite('Encoding Zooms', () => {
    test('no zoom low', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x3fffffff,
        0x80000001,
      );
      assert.equal(low, 0x3fffffff);
      assert.equal(high, 0x80000001);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom low', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x3fffffff,
        0x80000000,
      );
      assert.equal(low, 0x7ffffffe);
      assert.equal(high, 0); // 2^32 - MAX
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (lower)', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x40000000,
        0x80000001,
      );
      assert.equal(low, 0);
      assert.equal(high, 0x80000002);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('no zoom high', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x7fffffff,
        0xc0000001,
      );
      assert.equal(low, 0x7fffffff);
      assert.equal(high, 0xc0000001);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 0);
    });
    test('single zoom high', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x80000000,
        0xc0000001,
      );
      assert.equal(low, 0);
      assert.equal(high, 0x80000002); // 2^32 - MAX
      assert.equal(outerZooms, 1);
      assert.equal(midZooms, 0);
    });
    test('single zoom mid (higher)', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x7fffffff,
        0xc0000000,
      );
      assert.equal(low, 0x7ffffffe);
      assert.equal(high, 0); // 2^32
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 1);
    });
    test('max zooms low', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(0, 2);
      assert.equal(low, 0);
      assert.equal(high, 0);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms high', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(0xfffffffe, 0);
      assert.equal(low, 0);
      assert.equal(high, 0);
      assert.equal(outerZooms, 31);
      assert.equal(midZooms, 0);
    });
    test('max zooms mid', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0x7fffffff,
        0x80000001,
      );
      assert.equal(low, 0);
      assert.equal(high, 0);
      assert.equal(outerZooms, 0);
      assert.equal(midZooms, 31);
    });
    test('many zooms arbitrary', () => {
      const [low, high, outerZooms, midZooms] = webaric.zoom(
        0b10110101001010110101001010011110,
        0b10110101001010110101001010100001,
      );
      assert.equal(low, 0);
      assert.equal(high, 0xc0000000);
      assert.equal(outerZooms, 26);
      assert.equal(midZooms, 4);
    });
  });
});
