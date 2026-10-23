const fs = require('node:fs');
const path = require('node:path');
const config = require(process.env.WPSM_CONFIG || '../config.json');
const ROOT = path.resolve(process.env.WPSM_WORKDIR || path.join(__dirname, '..'));
const origin = new URL(config.origin);
const allowed = new Set(config.includeHosts.map(s=>s.toLowerCase()));
const sleep = ms => new Promise(r=>setTimeout(r,ms));
function mkdir(file) { fs.mkdirSync(path.dirname(file), {recursive:true}); }
function write(file, data) { mkdir(file); fs.writeFileSync(file,data); }
function charsetFromContentType(contentType='') {
  const match=String(contentType).match(/charset\s*=\s*["']?([^\s;"']+)/i);
  return match?.[1]||'';
}
function charsetFromMarkup(buffer) {
  // Charset declarations are ASCII, so a latin1 view can inspect them without
  // first knowing the document encoding. Limit the scan to the document head.
  const prefix=buffer.subarray(0,4096).toString('latin1');
  const direct=prefix.match(/<meta\b[^>]*\bcharset\s*=\s*["']?\s*([^\s"'/>;]+)/i);
  if(direct)return direct[1];
  const legacy=prefix.match(/<meta\b[^>]*\bcontent\s*=\s*["'][^"']*charset\s*=\s*([^\s;"']+)/i);
  return legacy?.[1]||'';
}
function bomCharset(buffer) {
  if(buffer.length>=3&&buffer[0]===0xef&&buffer[1]===0xbb&&buffer[2]===0xbf)return 'utf-8';
  if(buffer.length>=2&&buffer[0]===0xff&&buffer[1]===0xfe)return 'utf-16le';
  if(buffer.length>=2&&buffer[0]===0xfe&&buffer[1]===0xff)return 'utf-16be';
  return '';
}
function decodeBuffer(buffer,contentType='',inspectMarkup=true) {
  const charset=bomCharset(buffer)||charsetFromContentType(contentType)||(inspectMarkup?charsetFromMarkup(buffer):'')||'utf-8';
  try{return new TextDecoder(charset).decode(buffer);}
  catch{return new TextDecoder('utf-8').decode(buffer);}
}
function urlOf(raw, base=config.origin) { try { return new URL(raw,base); } catch {return null;} }
function isPage(u) {
  if (!u || !/^https?:$/.test(u.protocol) || !allowed.has(u.hostname.toLowerCase())) return false;
  if (config.excludePathPrefixes.some(p=>u.pathname.startsWith(p))) return false;
  if (u.pathname.split('/').some(part=>part==='..')) return false;
  if (/\.(?:png|jpe?g|gif|webp|avif|svg|ico|css|js|mjs|woff2?|ttf|eot|otf|pdf|zip|xml|txt|mp4|webm|mp3|json)$/i.test(u.pathname)) return false;
  return true;
}
function pageKey(u) { return u.pathname + (u.search||''); }
function pageFile(u) {
  let p = u.pathname;
  if (!p.endsWith('/')) p += '/';
  if (u.search) { const suffix = require('node:crypto').createHash('sha1').update(u.search).digest('hex').slice(0,10); p = p.replace(/\/$/,'') + '--query-' + suffix + '/'; }
  return path.join(ROOT,'src','pages',p.replace(/^\/+/,''),'index.html');
}
function outputFile(u) {return path.join(ROOT,'dist',path.relative(path.join(ROOT,'src','pages'),pageFile(u)));}
function assetPath(u) {
  const safePath = u.pathname;
  const suffix = u.search ? '--'+require('node:crypto').createHash('sha1').update(u.search).digest('hex').slice(0,10):'';
  const ext = path.posix.extname(safePath); const stem = ext?safePath.slice(0,-ext.length):safePath;
  return '/_mirror/'+u.hostname+stem+suffix+(ext||'.bin');
}
function publicUrl(raw,base) {
  const u=urlOf(raw,base);
  if(!u || !/^https?:$/.test(u.protocol) || !allowed.has(u.hostname.toLowerCase())) return raw;
  if(isPage(u)) { let p=u.pathname; if(!p.endsWith('/'))p+='/'; if(u.search) {const hash=require('node:crypto').createHash('sha1').update(u.search).digest('hex').slice(0,10);p=p.replace(/\/$/,'')+'--query-'+hash+'/';}return p+u.hash; }
  return assetPath(u)+u.hash;
}
async function get(u) {
  const c=new AbortController(); const timer=setTimeout(()=>c.abort(),config.timeoutMs);
  try {const r=await fetch(u,{signal:c.signal,redirect:'follow',headers:{'user-agent':config.userAgent}});if(!allowed.has(new URL(r.url).hostname.toLowerCase()))throw Error('Redirect outside allowed hosts');if(!r.ok)throw Error('HTTP '+r.status);return r;} finally {clearTimeout(timer);}
}
module.exports={ROOT,config,origin,sleep,write,decodeBuffer,urlOf,isPage,pageKey,pageFile,outputFile,assetPath,publicUrl,get,allowed};
