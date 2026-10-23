const test=require('node:test');
const assert=require('node:assert/strict');
const {decodeBuffer}=require('../scripts/common');

test('decodes EUC-JP declared by an HTML meta element',()=>{
  const source='<!doctype html><meta http-equiv="Content-Type" content="text/html; charset=EUC-JP"><title>東京コンタクト</title>';
  const bytes=Buffer.from(new TextEncoder().encode(source));
  const marker=Buffer.from(new TextEncoder().encode('東京コンタクト'));
  // EUC-JP bytes for 東京コンタクト. Keeping the fixture inline avoids a
  // test-only encoding dependency.
  const japanese=Buffer.from('c5ecb5fea5b3a5f3a5bfa5afa5c8','hex');
  const encoded=Buffer.concat([bytes.subarray(0,bytes.indexOf(marker)),japanese,bytes.subarray(bytes.indexOf(marker)+marker.length)]);
  assert.match(decodeBuffer(encoded,'text/html'),/<title>東京コンタクト<\/title>/);
});

test('HTTP charset takes precedence over a conflicting meta declaration',()=>{
  const source='<meta charset="EUC-JP"><p>日本語</p>';
  const bytes=Buffer.from(source,'utf8');
  assert.match(decodeBuffer(bytes,'text/html; charset=UTF-8'),/<p>日本語<\/p>/);
});
