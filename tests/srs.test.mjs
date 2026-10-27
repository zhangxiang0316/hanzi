import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const srs = require('../miniprogram/utils/srs.js');

test('新字学习后进入箱子 1，明天复习', () => {
  const e = srs.learn(null, 100);
  assert.equal(e.box, 1);
  assert.equal(e.due, 101);
  assert.equal(srs.stageOf(e), 'learning');
});

test('重复 learn 不会降级或重复加箱', () => {
  const e = srs.grade(srs.learn(null, 0), true, 10); // box 2
  const again = srs.learn(e, 11);
  assert.equal(again, e);
});

test('答对升箱，间隔变长', () => {
  let e = srs.learn(null, 0);
  const days = [];
  for (let i = 0; i < 6; i++) {
    e = srs.grade(e, true, 100);
    days.push(e.due - 100);
  }
  assert.deepEqual(days, [2, 4, 7, 15, 30, 60]);
  assert.equal(e.box, 7);
  assert.equal(srs.stageOf(e), 'mastered');
});

test('答错回退：熟字退到 1，生字退到 0', () => {
  let e = { box: 5, seen: 3, ok: 3, miss: 0, due: 0, last: 0 };
  e = srs.grade(e, false, 50);
  assert.equal(e.box, 1);
  assert.equal(e.miss, 1);
  let f = { box: 1, seen: 1, ok: 1, miss: 0, due: 0, last: 0 };
  f = srs.grade(f, false, 50);
  assert.equal(f.box, 0);
});

test('due 判断按天', () => {
  const e = { box: 1, due: 105 };
  assert.equal(srs.isDue(e, 104), false);
  assert.equal(srs.isDue(e, 105), true);
  assert.equal(srs.isDue(e, 106), true);
  assert.equal(srs.isDue(null, 106), false);
});

test('markKnown 至少到 4 箱', () => {
  const e = srs.markKnown(srs.learn(null, 0), 0);
  assert.equal(e.box, 4);
  assert.equal(e.due, 7);
  assert.equal(e.known, true);
});
