/** base64 → Uint8Array，兼容小程序 / Node / 浏览器预览 */
function toBytes(b64) {
  if (typeof wx !== 'undefined' && typeof wx.base64ToArrayBuffer === 'function') {
    try {
      return new Uint8Array(wx.base64ToArrayBuffer(b64));
    } catch (e) {
      // fall through
    }
  }
  if (typeof Buffer !== 'undefined') {
    return new Uint8Array(Buffer.from(b64, 'base64'));
  }
  if (typeof atob === 'function') {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  throw new Error('当前环境不支持 base64 解码');
}

module.exports = { toBytes };
