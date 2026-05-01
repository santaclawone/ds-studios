function BuildProspectHtml($r, $emailText) {
  $issuesJson = $r.issues | ConvertTo-Json -Depth 5
  $positivesJson = $r.positives | ConvertTo-Json -Depth 3

  # Escape for JS string
  $emailEscaped = $emailText -replace "\\","\\\\" -replace "'","\\'" -replace "`r`n","\n" -replace "`n","\n"

@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
<title>Prospect Review — $($r.businessName) — DS Studios</title>
<meta name="robots" content="noindex,nofollow">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f0f13;color:#fff;overflow:hidden;height:100dvh;display:flex;flex-direction:column;user-select:none;-webkit-user-select:none}
.card-stack{flex:1;position:relative;overflow:hidden;padding:16px 12px 8px}
#card-container{position:relative;width:100%;height:100%;max-width:420px;margin:0 auto}
.card{position:absolute;top:0;left:0;width:100%;height:100%;background:linear-gradient(160deg,#1a1a24,#12121a);border-radius:18px;padding:24px 20px 18px;box-shadow:0 8px 40px rgba(0,0,0,.5);border:1px solid rgba(255,255,255,.06);display:flex;flex-direction:column;transition:transform .3s ease,opacity .3s ease;will-change:transform;overflow:hidden;touch-action:none}
.card-top{flex:1;overflow-y:auto;scrollbar-width:thin;scrollbar-color:rgba(255,255,255,.1) transparent;padding-right:4px}
.card-top::-webkit-scrollbar{width:3px}
.card-top::-webkit-scrollbar-thumb{background:rgba(255,255,255,.1);border-radius:2px}
.card.sending{transition:transform .35s ease,opacity .35s ease}
.card.sent-left{transform:translateX(-120%) rotate(-12deg);opacity:0}
.card.sent-right{transform:translateX(120%) rotate(12deg);opacity:0}
.badge{display:inline-block;font-size:9px;font-weight:700;padding:2px 8px;border-radius:4px;text-transform:uppercase;letter-spacing:.3px;margin-bottom:8px}
.badge.critical{background:rgba(239,68,68,.2);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
.badge.high{background:rgba(245,158,11,.2);color:#f59e0b;border:1px solid rgba(245,158,11,.3)}
.badge.medium{background:rgba(59,130,246,.2);color:#60a5fa;border:1px solid rgba(59,130,246,.3)}
.badge.low{background:rgba(156,163,175,.15);color:#9ca3af;border:1px solid rgba(156,163,175,.2)}
.card h2{font-size:18px;font-weight:700;letter-spacing:-.3px;margin-bottom:4px;line-height:1.2}
.card .detail{font-size:13px;color:#a0a0b0;line-height:1.55;margin-bottom:12px}
.card .check-label{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;color:#6b7280;margin-bottom:4px}
.card .check{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:8px;padding:8px 10px;font-size:11px;color:#9ca3af;line-height:1.4;margin-bottom:6px}
.card .check strong{color:#d1d5db}
.card .cta-row{display:flex;gap:6px;margin-top:4px;flex-shrink:0}
.card .cta-row a{flex:1;text-align:center;padding:8px;border-radius:8px;font-size:11px;font-weight:600;text-decoration:none;border:1px solid rgba(255,255,255,.1);color:#a0a0b0;background:rgba(255,255,255,.04)}
.card .cta-row a:hover{background:rgba(255,255,255,.08);color:#fff}
.indicators{display:flex;justify-content:center;gap:5px;padding:6px 0 10px;flex-shrink:0}
.dot{width:6px;height:6px;border-radius:50%;background:rgba(255,255,255,.15);transition:all .2s}
.dot.active{background:#6366f1;width:18px;border-radius:3px}
.footer-btns{display:flex;gap:8px;padding:6px 12px 16px;flex-shrink:0;max-width:420px;margin:0 auto;width:100%}
.footer-btns button{flex:1;padding:12px;border:0;border-radius:12px;font-size:13px;font-weight:600;cursor:pointer;transition:transform .05s}
.footer-btns button:active{transform:scale(.96)}
.btn-pass{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.2)!important}
.btn-check{background:rgba(99,102,241,.15);color:#818cf8;border:1px solid rgba(99,102,241,.2)!important}
.btn-send{background:rgba(34,197,94,.15);color:#22c55e;border:1px solid rgba(34,197,94,.2)!important}
.done-screen{display:none;flex-direction:column;align-items:center;justify-content:center;text-align:center;height:100%;padding:20px}
.done-screen.visible{display:flex}
.done-screen .e{font-size:48px;margin-bottom:10px}
.done-screen h2{font-size:20px;margin-bottom:4px}
.done-screen p{font-size:12px;color:#9ca3af;margin-bottom:16px;line-height:1.5;max-width:360px}
.done-screen .outcome{font-size:11px;padding:6px 14px;border-radius:6px;margin-bottom:12px}
.outcome.go{background:rgba(34,197,94,.12);color:#22c55e;border:1px solid rgba(34,197,94,.15)}
.outcome.no{background:rgba(239,68,68,.12);color:#ef4444;border:1px solid rgba(239,68,68,.15)}
.email-box{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:12px;max-height:200px;overflow-y:auto;width:100%;text-align:left;font-size:10px;color:#9ca3af;line-height:1.5;white-space:pre-wrap;margin-bottom:10px}
.done-screen button{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.1);color:#fff;padding:10px 24px;border-radius:10px;font-size:12px;font-weight:600;cursor:pointer}
.done-screen button:hover{background:rgba(255,255,255,.12)}
.header{display:flex;align-items:center;gap:10px;padding:12px 16px 0;flex-shrink:0;max-width:420px;margin:0 auto;width:100%}
.header .info{flex:1}
.header .name{font-size:15px;font-weight:700}
.header .sub{font-size:10px;color:#6b7280}
.header .sb{font-weight:800;padding:4px 10px;border-radius:20px;font-size:12px}
.good{color:#22c55e}.ok{color:#f59e0b}.bad{color:#ef4444}
.ra{display:flex;flex-direction:column;gap:8px;width:100%;margin-top:4px;flex-shrink:0}
.ra .rw{display:flex;gap:6px}
.ra button{flex:1;padding:10px;border:0;border-radius:10px;font-size:11px;font-weight:600;cursor:pointer}
.ra .go{background:#22c55e;color:#000}
.ra .sp{background:rgba(255,255,255,.06);color:#9ca3af;border:1px solid rgba(255,255,255,.1)!important}
.ra .cp{background:rgba(99,102,241,.15);color:#818cf8;border:1px solid rgba(99,102,241,.2)!important}
</style>
</head>
<body>
<div class="header" id="hdr"></div>
<div class="card-stack" id="stack"><div id="card-container"></div><div class="indicators" id="dots"></div></div>
<div class="footer-btns" id="ftr">
  <button class="btn-pass" onclick="sw('left')">✕ Skip</button>
  <button class="btn-check" onclick="openSite()">🔍 Check Site</button>
  <button class="btn-send" onclick="sw('right')">✓ Looks Good</button>
</div>
<div class="done-screen" id="done">
  <div class="e">🎯</div>
  <h2>All Reviewed</h2>
  <p id="dtxt">You've gone through every issue.</p>
  <div class="outcome" id="obadge"></div>
  <div class="email-box" id="eprev"></div>
  <div class="ra">
    <div class="rw">
      <button class="go" id="btn-copy" onclick="cp()">📋 Copy & Send</button>
      <button class="sp" onclick="rs()">↺ Review Again</button>
    </div>
    <div class="rw">
      <button class="cp" onclick="cp()">Copy Email Text</button>
      <button class="sp" onclick="openSite()">Open Website</button>
    </div>
  </div>
</div>
<script>
const D = $($r | ConvertTo-Json -Depth 5);
const ET = '$emailEscaped';
let ci=0,v=null,anim=false;

function ih(){const h=document.getElementById('hdr'),s=D.score,cl=s>=70?'good':s>=40?'ok':'bad'
h.innerHTML='<div class="info"><div class="name">'+D.businessName+'</div><div class="sub">'+D.url+' · '+D.issues.length+' issues</div></div><div class="sb '+cl+'">'+s+'/100</div>'}

function rc(){const c=document.getElementById('card-container'),cards=D.issues;if(ci>=cards.length){sd();return}
c.innerHTML='';for(let i=0;i<Math.min(3,cards.length-ci);i++){const cd=cards[ci+i],div=document.createElement('div');div.className='card';div.style.zIndex=3-i;div.style.transform=i>0?'scale('+(1-i*.03)+') translateY('+(i*6)+'px)':'none';div.style.opacity=i>0?.6:1
div.innerHTML='<div class="card-top"><span class="badge '+cd.severity+'">'+cd.severity+'</span><h2>'+cd.label+'</h2><div class="detail">'+cd.detail+'</div><div class="check-label">What to check</div><div class="check">'+cd.check+'</div><div class="check-label">Why it matters</div><div class="check">'+cd.siteHint+'</div><div class="cta-row"><a href="'+D.url+'" target="_blank">🔍 Open site</a><a href="'+D.url+'" target="_blank">📋 DevTools</a></div></div>'
if(i===0){let sx=0;div.addEventListener('touchstart',e=>{if(anim)return;sx=e.touches[0].clientX;div.style.transition='none'},{passive:true})
div.addEventListener('touchmove',e=>{if(anim||!sx)return;const dx=e.touches[0].clientX-sx;if(Math.abs(dx)<5)return;div.style.transform='translateX('+dx+'px) rotate('+(dx*.08)+'deg)';div.style.opacity=1-Math.abs(dx)/600},{passive:true})
div.addEventListener('touchend',e=>{if(anim||!sx)return;const dx=e.changedTouches[0].clientX-sx;div.style.transition='transform .35s ease, opacity .35s ease';if(Math.abs(dx)>80)sw(dx>0?'right':'left');else{div.style.transform='none';div.style.opacity=1}sx=0},{passive:true})}
c.appendChild(div)}ud()}

function ud(){const d=document.getElementById('dots');d.innerHTML='';for(let i=0;i<D.issues.length;i++){const dot=document.createElement('div');dot.className='dot'+(i===ci?' active':'');d.appendChild(dot)}}

function sw(dir){if(anim||ci>=D.issues.length)return;anim=true;const tc=document.querySelector('.card');if(!tc)return;tc.classList.add('sending',dir==='right'?'sent-right':'sent-left')
if(dir==='right')v='send';setTimeout(()=>{ci++;rc();ud();anim=false;document.getElementById('ftr').style.display=ci>=D.issues.length?'none':'flex'},350)}

function openSite(){window.open(D.url,'_blank')}

function sd(){document.getElementById('stack').style.display='none';document.getElementById('ftr').style.display='none';document.getElementById('done').classList.add('visible')
const b=document.getElementById('obadge'),t=document.getElementById('dtxt'),ep=document.getElementById('eprev')
if(v==='send'){b.className='outcome go';b.textContent='DECISION: SEND';t.textContent='Prospect passed the sniff test. Email draft is ready to go.'}
else{b.className='outcome no';b.textContent='DECISION: SKIP';t.textContent='This one needs more vetting or better targets exist.'}
ep.textContent=ET}

async function cp(){try{await navigator.clipboard.writeText(ET);const btn=document.getElementById('btn-copy');const orig=btn.textContent;btn.textContent='Copied!';setTimeout(()=>btn.textContent=orig,1500)}catch(e){alert('Email:\n\n'+ET)}}
function rs(){ci=0;v=null;document.getElementById('stack').style.display='block';document.getElementById('done').classList.remove('visible');document.getElementById('ftr').style.display='flex';rc();ud()}
document.addEventListener('keydown',e=>{if(document.getElementById('done').classList.contains('visible')){if(e.key==='r')rs();if(e.key==='c')cp();return}if(e.key==='ArrowLeft')sw('left');if(e.key==='ArrowRight')sw('right');if(e.key==='o')openSite()})
ih();rc();ud()
</script>
</body></html>
"@
}

Export-ModuleMember -Function BuildProspectHtml
