// Comprobaciones rápidas de TORNEAZO (se ejecutan solas en cada PR).
const fs=require('fs'),http=require('http'),path=require('path');
let pw;try{pw=require('playwright')}catch(e){pw=require('playwright-core')}
const {chromium}=pw;
const root=path.join(__dirname,'..');
let fallos=0;const ko=m=>{console.error('FALLA: '+m);fallos++},ok=m=>console.log('ok: '+m);

// 1) Archivos clave no vacíos y JSON válido
for(const f of ['index.html','app.js','sw.js','version.json','config.js','manifest.webmanifest']){
  const t=fs.readFileSync(path.join(root,f),'utf8');t.trim().length>200?ok(f+' tiene contenido'):ko(f+' está vacío o roto');
}
try{JSON.parse(fs.readFileSync(path.join(root,'version.json'),'utf8'));ok('version.json es JSON válido')}catch(e){ko('version.json no es JSON válido')}

// 2) Las tres versiones coinciden
const vj=JSON.parse(fs.readFileSync(path.join(root,'version.json'),'utf8')).version;
const va=(fs.readFileSync(path.join(root,'app.js'),'utf8').match(/APP_VERSION='([^']+)'/)||[])[1];
const vs=(fs.readFileSync(path.join(root,'sw.js'),'utf8').match(/VERSION\s*=\s*"([^"]+)"/)||[])[1];
(vj===va&&va===vs)?ok('versión '+vj+' igual en version.json, app.js y sw.js'):ko(`versiones distintas: version.json=${vj} app.js=${va} sw.js=${vs}`);
const h0=JSON.parse(fs.readFileSync(path.join(root,'version.json'),'utf8')).historial[0];
(h0&&h0.version===vj&&h0.cambios&&h0.cambios.length)?ok('la última novedad corresponde a la versión'):ko('la primera entrada de historial no coincide con la versión');

// 3) La app arranca en un servidor local, sin errores, y sortea
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.webmanifest':'application/manifest+json','.png':'image/png','.css':'text/css'};
const srv=http.createServer((q,r)=>{let p=path.join(root,decodeURIComponent(q.url.split('?')[0]));if(p.endsWith(path.sep))p+='index.html';
  if(!p.startsWith(root)||!fs.existsSync(p)||fs.statSync(p).isDirectory()){r.writeHead(404);return r.end()}
  r.writeHead(200,{'Content-Type':mime[path.extname(p)]||'application/octet-stream'});fs.createReadStream(p).pipe(r)});
(async()=>{
  await new Promise(r=>srv.listen(8791,r));
  const b=await chromium.launch(process.env.CI?{channel:'chrome'}:{}),p=await b.newPage(),errs=[];
  p.on('pageerror',e=>errs.push(e.message));
  p.on('console',m=>{if(m.type()=='error'&&/Content Security Policy|Refused to/.test(m.text()))errs.push(m.text())});
  await p.goto('http://localhost:8791/');await p.waitForTimeout(1500);
  const r=await p.evaluate(()=>{try{closeModal();S.players='Ana\nBea\nCarlos\nDavid';draw();return {grupos:(S.groupsList||[]).length,partidos:(S.matches||[]).length}}catch(e){return {error:String(e)}}});
  (r.partidos>0)?ok('el sorteo genera '+r.partidos+' partidos'):ko('el sorteo no funciona: '+JSON.stringify(r));
  // todas las funciones de data-click del HTML generado deben estar en la lista permitida
  const mal=await p.evaluate(()=>{const s=new Set();document.querySelectorAll('[data-click]').forEach(e=>{const m=/^\s*([A-Za-z_]\w*)\s*\(/.exec(e.getAttribute('data-click'));if(m&&!OK_FN.has(m[1]))s.add(m[1])});return [...s]});
  mal.length?ko('funciones fuera de OK_FN: '+mal.join(', ')):ok('todos los data-click están permitidos');
  errs.length?ko('errores en la página: '+errs.join(' | ')):ok('sin errores en la consola');
  await b.close();srv.close();
  if(fallos){console.error(fallos+' comprobación(es) fallida(s)');process.exit(1)}console.log('Todo bien');
})();
