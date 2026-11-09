#!/usr/bin/env node
// Reproduce app-sized assets from the approved Bard vector masters. Resource
// names deliberately remain stable so both apps update the existing library.
// App headings use native text in the interface font; no image wordmark ships.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const masters = path.join(root, 'Support/Brand/Bard');
const resources = path.join(root, 'Sources/Wisp/Resources');
const catalog = path.join(root, 'iOS/Resources/Assets.xcassets');
const renderer = process.env.BARD_RSVG_CONVERT || 'rsvg-convert';
const outputs = [];
function render(source, destination, maximum) {
  const file = path.join(masters, source+'.svg');
  const svg = fs.readFileSync(file, 'utf8');
  const viewBox = svg.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number);
  const scale = maximum / Math.max(viewBox[2], viewBox[3]);
  const width = Math.round(viewBox[2]*scale), height = Math.round(viewBox[3]*scale);
  execFileSync(renderer, ['-w', String(width), '-h', String(height), '-o', destination, file]);
  outputs.push({source:path.relative(root,file),target:path.relative(root,destination),width,height,
    sha256:crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')});
}
for (const [source, target, maximum] of [
  ['bard-insignia','wisp-insignia',2048], ['bard-app-icon','wisp-mark',2048],
  ['bard-cover','mixtape-cover',2048], ['briggs-maker-mark-gold','maker-mark',512],
]) {
  render(source,path.join(resources,target+'.png'),maximum);
  if (['wisp-insignia','maker-mark'].includes(target)) {
    render(source,path.join(catalog,target+'.imageset',target+'.png'),target==='maker-mark'?256:1024);
  }
}
const reportDirectory = path.join(root, 'build/brand');
fs.mkdirSync(reportDirectory, {recursive:true});
fs.writeFileSync(path.join(reportDirectory,'bard-brand-integration.json'),JSON.stringify({method:'Native raster exports from approved scalable masters; stable internal resource names',outputs},null,2)+'\n');
console.log('Bard assets prepared for Mac and iPhone. Run iOS/scripts/prepare-icon.sh for the phone app icons.');
