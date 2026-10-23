#!/usr/bin/env node
'use strict';
const fs=require('node:fs');const path=require('node:path');const {spawnSync}=require('node:child_process');
const args=process.argv.slice(2);const command=args[0]||'help';
function option(name){const i=args.indexOf('--'+name);return i>=0?args[i+1]:undefined;}
function usage(){console.log(`WP Static Migrator v0.1.0
  wp-static-migrator init --url https://example.com --output ./my-site
  wp-static-migrator crawl --output ./my-site
  wp-static-migrator build --output ./my-site
  wp-static-migrator validate --output ./my-site
  wp-static-migrator all --output ./my-site
  wp-static-migrator report --output ./my-site
  wp-static-migrator preview --output ./my-site --port 8080

Only crawl sites you own or have permission to migrate.`);}
const root=path.resolve(__dirname,'..');
if(command==='help'||args.includes('--help')){usage();process.exit(0);}
const dir=path.resolve(option('output')||'./wp-static-output');
if(command==='init'){
 const raw=option('url');if(!raw){usage();process.exit(2);}
 let url;try{url=new URL(raw);if(!['http:','https:'].includes(url.protocol))throw Error('invalid protocol');}catch{console.error('Invalid --url');process.exit(2);}
 fs.mkdirSync(dir,{recursive:true});
 const config=JSON.parse(fs.readFileSync(path.join(root,'config.json'),'utf8'));
 config.origin=url.origin;config.startPaths=[url.pathname||'/'];config.includeHosts=[url.hostname];
 const conf=path.join(dir,'config.json');if(fs.existsSync(conf)){console.error('config.json already exists; refusing to overwrite');process.exit(2);}
 fs.writeFileSync(conf,JSON.stringify(config,null,2)+'\n');
 fs.mkdirSync(path.join(dir,'src','layouts'),{recursive:true});
 fs.copyFileSync(path.join(root,'src','layouts','default.html'),path.join(dir,'src','layouts','default.html'));
 console.log('Initialized:',dir);console.log('Review config.json, then run: wp-static-migrator all --output',dir);process.exit(0);
}
if(!['crawl','build','validate','all','report','preview'].includes(command)){usage();process.exit(2);}
if(!fs.existsSync(path.join(dir,'config.json'))){console.error('Missing config.json. Run init first.');process.exit(2);}
if(command==='preview'){
 const portRaw=option('port')||'8080';
 const port=Number(portRaw);
 if(!/^\d+$/.test(portRaw)||!Number.isInteger(port)||port<1||port>65535){console.error('Invalid --port (1-65535)');process.exit(2);}
 const r=spawnSync(process.execPath,[path.join(root,'scripts','preview.js')],{stdio:'inherit',env:{...process.env,WPSM_WORKDIR:dir,WPSM_PORT:String(port)}});
 process.exit(r.status===null?1:r.status);
}
if(command==='report'){
 for(const name of ['crawl-errors.json','shared-variants.json','validation.json']){
  const f=path.join(dir,'logs',name);console.log('\n'+name+':');console.log(fs.existsSync(f)?fs.readFileSync(f,'utf8'):'Not generated');
 }process.exit(0);
}
for(const task of (command==='all'?['crawl','build','validate']:[command])){
 const r=spawnSync(process.execPath,[path.join(root,'scripts',task+'.js')],{stdio:'inherit',env:{...process.env,WPSM_WORKDIR:dir,WPSM_CONFIG:path.join(dir,'config.json')}});
 if(r.status!==0)process.exit(r.status||1);
}
