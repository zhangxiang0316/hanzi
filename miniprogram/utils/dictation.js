/**
 * 听写 / 默写。
 *
 * **小程序端做不了真正的听写**：微信小程序没有系统 TTS API，本项目也是纯前端、
 * 没有后端可以调语音合成。所以这里的做法是「看词写」——把听觉输入换成视觉输入，
 * 看完之后凭记忆写，难度上仍然比描红高一档。
 *
 * App 端（Android/iOS）有系统 TTS，是真正的「念出来、听写」。
 * 两者刻意保持相同的评分与推进逻辑，只是题目呈现方式不同，
 * 页面上也会如实告诉用户「这一端是看词写，不是听写」。
 *
 * 与 iOS `DictationLevel`、Android `DictationLevel` 语义对应。
 */
const catalog = require('./catalog');

/** 这一端能否朗读。小程序恒为 false，App 端为 true。 */
const SUPPORTS_AUDIO = false;

/**
 * 三档难度。
 *
 * 之所以保留 easy 档：最难的是「根本想不起来这个字长什么样」。
 * 一上来就完全不给提示，一部分孩子会直接卡死在第一题，一题都写不出，
 * 从此不愿意再点这个入口。给一个可以从描红过渡的档位，
 * 比逼他们直接跳到最难的更可能坚持下去。
 */
const LEVELS = [
  {
    key: 'easy',
    title: '看着写',
    desc: '田字格里还有淡色的字',
    showsGhost: true,
    /** 题面显示多久后隐藏（0 = 一直显示） */
    peekMs: 0,
    needsAudio: false,
  },
  {
    key: 'normal',
    title: '看词写',
    desc: '看着词语，把字写出来（没有淡色的字）',
    showsGhost: false,
    peekMs: 0,
    needsAudio: false,
  },
  {
    key: 'hard',
    title: '记着写',
    desc: '词语只显示 3 秒就藏起来',
    showsGhost: false,
    peekMs: 3000,
    needsAudio: false,
  },
];

function levelOf(key) {
  return LEVELS.find((l) => l.key === key) || LEVELS[1];
}

/**
 * 题面文字。
 *
 * 有词给词、没词给字——「天空」比单念「天」更容易想起是哪个字。
 * hard 档不给词，只给这一个字（再配合 peekMs 自动隐藏）。
 */
function promptText(level, ch, word) {
  const lv = typeof level === 'string' ? levelOf(level) : level;
  if (lv.key === 'hard') return ch;
  return word || ch;
}

/**
 * 选听写的字。
 *
 * 优先级：本册「会写」的字 → 本册全部字 → 所有有笔顺数据的字。
 * 「会写」这个区分（`isWriteChar`）是教材自带的，之前三端都定义了却没用；
 * 听写场景下它正好合适——只认不写的字（髓、嚼、蟹）要求孩子默写出来没有道理。
 *
 * 顺序固定按教材顺序，而不是随机：听写是「今天学完这几课，默一遍」的场景，
 * 顺序对得上课文才有意义，随机打乱会让家长没法对照课本。
 */
function pick(book, levelKey, limit) {
  const level = levelOf(levelKey);
  const repo = catalog;
  let pool = repo.bookChars(book).filter((ch) => repo.isWriteChar(ch));
  if (pool.length < 4) pool = repo.bookChars(book);
  if (!pool.length) pool = repo.getAllChars();

  return pool.slice(0, Math.max(1, limit || 8)).map((ch) => {
    const meta = repo.getMeta(ch);
    // easy/normal 用第一个组词；hard 不显示词
    const word =
      level.key === 'hard' ? null : meta && meta.w && meta.w.length ? meta.w[0].w : null;
    return { ch, word };
  });
}

module.exports = { LEVELS, SUPPORTS_AUDIO, levelOf, promptText, pick };
