#!/bin/bash

mkdir -p dist
npx tsc
# Alternate:
#   npx -p wabt wat2wasm src/webaric.wat -o lib/webaric.wasm
sed -r '/DEBUG_START/{:b;N;s/DEBUG_END//;T b;d}' ./src/webaric.wat > ./dist/stripped.wat
npx wasm-as -all ./dist/stripped.wat -o ./dist/webaric_std.wasm
npx wasm-opt -all -O3 ./dist/webaric_std.wasm -o ./dist/webaric.wasm
rm ./dist/stripped.wat ./dist/webaric_std.wasm
npx esbuild ./src/webaric.ts --bundle --splitting --minify --format=esm --outdir=dist
npx html-minifier-terser --collapse-whitespace --remove-comments --minify-js true ./src/index.html -o ./dist/index.html
cp src/index.html dist/
