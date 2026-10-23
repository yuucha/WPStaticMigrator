const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {createServer}=require('../scripts/preview');
test('preview serves directory index and assets and rejects traversal',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'wpsm-preview-'));
 fs.mkdirSync(path.join(dir,'about'));
 fs.writeFileSync(path.join(dir,'index.html'),'<h1>Home</h1>');
 fs.writeFileSync(path.join(dir,'about','index.html'),'<h1>About</h1>');
 const server=createServer(dir);
 try{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  let r=await fetch(base+'/');assert.equal(r.status,200);assert.match(await r.text(),/Home/);
  r=await fetch(base+'/about/');assert.equal(r.status,200);assert.match(await r.text(),/About/);
  r=await fetch(base+'/missing');assert.equal(r.status,404);
  r=await fetch(base+'/%2e%2e/%2e%2e/etc/passwd');assert.notEqual(r.status,200);
 }finally{await new Promise(resolve=>server.close(resolve));fs.rmSync(dir,{recursive:true,force:true});}
});
