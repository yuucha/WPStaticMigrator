const fs=require('node:fs');const path=require('node:path');const Handlebars=require('handlebars');
const {ROOT,write}=require('./common');
const manifest=JSON.parse(fs.readFileSync(path.join(ROOT,'src','manifest.json'),'utf8'));
const components=path.join(ROOT,'src','components');
for(const name of ['header','navigation','footer']) {const p=path.join(components,name+'.html');Handlebars.registerPartial(name,fs.existsSync(p)?fs.readFileSync(p,'utf8'):'');}
const layout=Handlebars.compile(fs.readFileSync(path.join(ROOT,'src','layouts','default.html'),'utf8'),{noEscape:true});
for(const page of manifest){const content=fs.readFileSync(path.join(ROOT,'src','pages',page.path),'utf8');
 const html=layout({lang:page.lang,head:page.head,title:page.title,bodyClass:page.bodyClass,content});
 const file=path.join(ROOT,'dist',page.path);write(file,html);console.log('[BUILD]',page.path);
}
const urls=manifest.map(p=>`  <url><loc>${p.url.replace(/&/g,'&amp;')}</loc></url>`).join('\n');
write(path.join(ROOT,'dist','sitemap.xml'),`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`);
console.log(`Built ${manifest.length} HTML files.`);
