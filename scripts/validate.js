const fs=require('node:fs');const path=require('node:path');const cheerio=require('cheerio');
const {ROOT,write}=require('./common');
const manifest=JSON.parse(fs.readFileSync(path.join(ROOT,'src','manifest.json'),'utf8'));
const issues=[];
for(const p of manifest){const file=path.join(ROOT,'dist',p.path);if(!fs.existsSync(file)){issues.push({page:p.url,type:'missing-page',path:p.path});continue;}
 const $=cheerio.load(fs.readFileSync(file,'utf8'));
 for(const [sel,attr] of [['a[href]','href'],['img[src]','src'],['script[src]','src'],['link[rel="stylesheet"][href]','href']])$(sel).each((_,el)=>{
  const v=$(el).attr(attr);if(!v||!v.startsWith('/')||v.startsWith('//'))return;
  const pathname=decodeURIComponent(v.split(/[?#]/)[0]);if(!pathname)return;
  const f=path.join(ROOT,'dist',pathname.replace(/^\//,''));
  if(!fs.existsSync(f)&&!fs.existsSync(path.join(f,'index.html')))issues.push({page:p.url,type:'missing-reference',value:v});
 });
 if(/\/wp-json\/|admin-ajax\.php|wp-login\.php/i.test($.html()))issues.push({page:p.url,type:'wordpress-dependency-review'});
}
write(path.join(ROOT,'logs','validation.json'),JSON.stringify({pages:manifest.length,issues},null,2));
console.log(`Validated ${manifest.length} pages; ${issues.length} findings. See logs/validation.json`);
if(issues.length)process.exitCode=1;
