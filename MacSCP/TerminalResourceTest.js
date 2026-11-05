'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'Resources/terminal.html'),'utf8');
const references=[...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(x=>x[1]);
assert.deepEqual(references,['xterm.css','xterm.js','addon-fit.js']);
const bundle=path.join(root,'build/候选.noindex/MacSCP-Next.app/Contents/Resources');
for(const file of [...references,'xterm-LICENSE','xterm-addon-fit-LICENSE'])assert.ok(fs.statSync(path.join(bundle,file)).isFile(),file);
const messages=[],written=[],handlers={};
class Terminal{constructor(){}loadAddon(){}open(){}onData(fn){handlers.input=fn}onResize(fn){handlers.resize=fn}write(bytes){written.push(Buffer.from(bytes))}focus(){handlers.focused=true}}
class FitAddon{fit(){handlers.resize({cols:80,rows:24})}}
const context={Terminal,FitAddon:{FitAddon},Uint8Array,atob:text=>Buffer.from(text,'base64').toString('binary'),ResizeObserver:class{constructor(fn){this.fn=fn}observe(){this.fn()}},document:{getElementById:()=>({}),documentElement:{clientWidth:800,clientHeight:600}},webkit:{messageHandlers:{bridge:{postMessage:m=>messages.push(m)}}}};
context.window=context;
vm.runInNewContext(html.match(/<script>\s*([\s\S]*?)<\/script>/)[1],context);
assert.ok(messages.some(m=>m.type==='ready'));
assert.ok(messages.some(m=>m.type==='resize'&&m.cols===80&&m.rows===24));
handlers.input('pwd\r');assert.ok(messages.some(m=>m.type==='input'&&m.data==='pwd\r'));
const text='服务器 ✓\r\n',bytes=Buffer.from(text);context.receive(bytes.subarray(0,2).toString('base64'));context.receive(bytes.subarray(2).toString('base64'));
assert.equal(Buffer.concat(written).toString('utf8'),text);context.focusTerminal();assert.ok(handlers.focused);
console.log('PASS: standalone terminal assets packaged; ready/input/resize bridge and byte-preserving split UTF-8 output; no network or user terminal');
