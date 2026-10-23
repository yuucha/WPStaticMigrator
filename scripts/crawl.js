const fs=require('node:fs');const path=require('node:path');const cheerio=require('cheerio');
const {ROOT,config,origin,sleep,write,decodeBuffer,urlOf,isPage,pageKey,pageFile,assetPath,publicUrl,get,allowed}=require('./common');
const queue=config.startPaths.map(p=>new URL(p,origin));const seen=new Set();const assets=new Map();const manifest=[];const errors=[];
const SEL=config.selectors;
const sharedVariants=[];
function enqueueAsset(raw,base) {if(!raw || /^(?:data:|blob:|mailto:|tel:|javascript:|#)/i.test(raw))return;
 const u=urlOf(raw,base);if(!u || !/^https?:$/.test(u.protocol) || !allowed.has(u.hostname.toLowerCase()))return;
 assets.set(u.href,u);
}
function rewriteAttr($,selector,attr,base) {$(selector).each((_,el)=>{const v=$(el).attr(attr);if(!v)return;
 if(attr==='srcset'){const changed=v.split(',').map(s=>{const m=s.trim().match(/^(\S+)(\s+.*)?$/);if(!m)return s;enqueueAsset(m[1],base);return publicUrl(m[1],base)+(m[2]||'');});$(el).attr(attr,changed.join(', '));return;}
 enqueueAsset(v,base);$(el).attr(attr,publicUrl(v,base));});}
function extractFragment($,selector) {const node=$(selector).first();return node.length?$.html(node):'';}
function stripShared($,selector,fragment) {if(fragment)$(selector).first().remove();}
async function crawl() {
 while(queue.length && manifest.length<config.maxPages) {
  const u=queue.shift();if(!isPage(u)||seen.has(pageKey(u)))continue;seen.add(pageKey(u));
  try {const r=await get(u);if(!String(r.headers.get('content-type')).includes('text/html'))continue;
   const html=decodeBuffer(Buffer.from(await r.arrayBuffer()),r.headers.get('content-type')||'');const $=cheerio.load(html,{decodeEntities:false});
   // Generated files are always UTF-8. Remove legacy declarations before the
   // head is persisted so browsers do not reinterpret the converted bytes.
   $('meta[charset],meta[http-equiv]').filter((_,el)=>{
    const node=$(el);return node.is('[charset]')||(node.attr('http-equiv')||'').toLowerCase()==='content-type';
   }).remove();
   $('head').prepend('<meta charset="utf-8">');
   $('a[href]').each((_,a)=>{const v=$(a).attr('href');const target=urlOf(v,u);if(isPage(target)&&!seen.has(pageKey(target)))queue.push(target);});
   $('a[href]').each((_,a)=>{const v=$(a).attr('href');if(v)$(a).attr('href',publicUrl(v,u));});
   for(const [sel,attr] of [['img[src]','src'],['img[srcset]','srcset'],['source[src]','src'],['source[srcset]','srcset'],['script[src]','src'],['link[href]','href'],['video[poster]','poster'],['video[src]','src'],['audio[src]','src'],['iframe[src]','src'],['input[src]','src']]) {
    // Links to alternate pages, canonical, feeds and remote endpoints are not downloadable assets.
    if(sel==='link[href]') {$('link[href]').each((_,el)=>{const rel=($(el).attr('rel')||'').toLowerCase();if(!/(stylesheet|icon|preload|apple-touch-icon)/.test(rel))return;const v=$(el).attr('href');enqueueAsset(v,u);$(el).attr('href',publicUrl(v,u));});}
    else rewriteAttr($,sel,attr,u);
   }
   $('[style]').each((_,el)=>{const v=$(el).attr('style');if(!v)return;$(el).attr('style',v.replace(/url\(\s*(['"]?)([^)'"\s]+)\1\s*\)/g,(_,q,s)=>{enqueueAsset(s,u);return `url(${q}${publicUrl(s,u)}${q})`;}));});
   const title=$('title').first().text();const lang=$('html').attr('lang')||'ja';
   const header=extractFragment($,SEL.header);const footer=extractFragment($,SEL.footer);
   let navigation='';if(SEL.navigation && $(SEL.navigation).first().length && !$(SEL.navigation).first().parents(SEL.header).length && !$(SEL.navigation).first().parents(SEL.footer).length) navigation=extractFragment($,SEL.navigation);
   // First successful page supplies initial shared components; manually review before final build.
   const comps=path.join(ROOT,'src','components');
   for(const [name,value] of Object.entries({header,footer,navigation})) {const f=path.join(comps,name+'.html');if(value&&!fs.existsSync(f))write(f,value); else if(value && fs.existsSync(f) && fs.readFileSync(f,'utf8')!==value) sharedVariants.push({url:u.href,component:name});}
   stripShared($,SEL.header,header);stripShared($,SEL.footer,footer);if(navigation)stripShared($,SEL.navigation,navigation);
   const head=$('head').html()||'';const body=$('body').html()||'';
   const relative=path.relative(path.join(ROOT,'src','pages'),pageFile(u)).replace(/\\/g,'/');
   write(pageFile(u),body);
   manifest.push({url:u.href,path:relative,title,lang,head,bodyClass:$('body').attr('class')||'',htmlAttrs:$('html').attr()||{},bodyAttrs:$('body').attr()||{}});
   console.log(`[PAGE ${manifest.length}] ${u.href}`);
  } catch(e){errors.push({url:u.href,error:e.message});console.error('[ERROR]',u.href,e.message);}
  await sleep(config.delayMs);
 }
 // Download assets, including CSS referenced assets. Do not treat scripts as executable during crawl.
 const completed=new Set();
 while(assets.size) {const [href,u]=assets.entries().next().value;assets.delete(href);if(completed.has(href))continue;completed.add(href);
  try {const r=await get(u);const type=r.headers.get('content-type')||'';let buf=Buffer.from(await r.arrayBuffer());
   if(/text\/css/i.test(type)||/\.css$/i.test(u.pathname)){
    let css=decodeBuffer(buf,type,false);css=css.replace(/^\s*@charset\s+["'][^"']+["'];?/i,'@charset "UTF-8";');css=css.replace(/url\(\s*(['"]?)([^)'"\s]+)\1\s*\)/g,(_,q,v)=>{enqueueAsset(v,u);return `url(${q}${publicUrl(v,u)}${q})`;});
    css=css.replace(/@import\s+(['"])([^'"]+)\1/g,(_,q,v)=>{enqueueAsset(v,u);return `@import ${q}${publicUrl(v,u)}${q}`;});buf=Buffer.from(css);
   }
   write(path.join(ROOT,'dist',assetPath(u).slice(1)),buf);console.log('[ASSET]',u.href);
  }catch(e){errors.push({url:href,error:e.message});console.error('[ASSET ERROR]',href,e.message);}
  await sleep(config.delayMs);
 }
 write(path.join(ROOT,'src','manifest.json'),JSON.stringify(manifest,null,2));
 write(path.join(ROOT,'logs','crawl-errors.json'),JSON.stringify(errors,null,2));
 write(path.join(ROOT,'logs','shared-variants.json'),JSON.stringify(sharedVariants,null,2));
 console.log(`Done: ${manifest.length} pages, ${completed.size} assets, ${errors.length} errors`);
}
crawl().catch(e=>{console.error(e);process.exitCode=1;});
