'use client';
/* eslint-disable */
// Renders the scenes for the README GIFs with the real CIFRO components and fictional data.
// It lives here as a reference: to run it, copy it to app/media-scenes/page.tsx in the CIFRO app,
// start `npm run dev`, and run capture.mjs. Remove it from the app afterwards.
import {useCallback,useEffect,useMemo,useState} from 'react';
import {TelegramLink} from '../telegram-link';
import {TransactionRows} from '../finance-ui';
import {BrandSymbol} from '../brand';
import {Send} from '@/components/icons';
import {baseTransaction,demoState,today,type Account,type Transaction} from '@/lib/finance';

type Msg={id:number;kind:'me'|'bot'|'typing';text:string};
type W=Window&{scene?:any;__linked?:boolean;__ready?:boolean};

const accounts:Account[]=[{id:'a1',name:'Conta principal',kind:'salary',initial:0,date:'2026-01-01',archived:false,order:0},{id:'a2',name:'Reserva de emergência',kind:'reserve',initial:0,date:'2026-01-01',archived:false,order:1}];

const nodes=[
  {n:'Telegram Trigger',x:0,y:0},{n:'Interpretar mensagem',x:224,y:0},{n:'É conexão?',x:448,y:0},
  {n:'Confirmar conexão',x:704,y:-240},{n:'Responder conexão',x:992,y:-240},{n:'É despesa?',x:704,y:96},
  {n:'Gravar no Cifro',x:992,y:0},{n:'Gravou?',x:1248,y:-96},{n:'Confirmar no Telegram',x:1536,y:-192},
  {n:'Avisar falha no Telegram',x:1536,y:48},{n:'Orientar no Telegram',x:992,y:240},
];
const edges:[string,string,number][]=[
  ['Telegram Trigger','Interpretar mensagem',0],['Interpretar mensagem','É conexão?',0],['É conexão?','Confirmar conexão',0],['É conexão?','É despesa?',1],
  ['Confirmar conexão','Responder conexão',0],['Confirmar conexão','Responder conexão',1],['É despesa?','Gravar no Cifro',0],['É despesa?','Orientar no Telegram',1],
  ['Gravar no Cifro','Gravou?',0],['Gravar no Cifro','Avisar falha no Telegram',1],['Gravou?','Confirmar no Telegram',0],['Gravou?','Avisar falha no Telegram',1],
];
const NW=108,NH=46,SX=0.545,SY=0.75,OX=26,OY=257;
const pos=(n:string)=>{const p=nodes.find(x=>x.n===n)!;return {x:OX+p.x*SX,y:OY+p.y*SY}};
const wrap=(s:string)=>{if(s.length<=15)return [s];const i=s.lastIndexOf(' ',Math.ceil(s.length/2)+3);return [s.slice(0,i),s.slice(i+1)]};

const css=`
html,body{margin:0;background:var(--background)}
nextjs-portal{display:none!important}
.stage{position:relative;width:1000px;height:560px;overflow:hidden;box-sizing:border-box;padding:0 40px;display:flex;align-items:center;justify-content:center;gap:48px;font-family:var(--font-sans,Manrope,sans-serif)}
.stage .left{width:590px;flex:none}
.stage .phone-wrap{flex:none;transform:scale(1.14);transform-origin:center}
.stage .telegram-bubble{animation-delay:0ms!important}
.stage .telegram-phone-chat{justify-content:flex-end}
.start-bar{margin:0 10px 12px;padding:9px;border-radius:12px;text-align:center;font-size:.7rem;font-weight:700;letter-spacing:.08em;color:var(--on-primary);background:var(--primary)}
.typing{display:inline-flex;gap:4px;padding:10px 12px}
.typing i{width:5px;height:5px;border-radius:50%;background:var(--text-secondary);animation:blink 1s infinite}
.typing i:nth-child(2){animation-delay:.15s}.typing i:nth-child(3){animation-delay:.3s}
@keyframes blink{0%,60%,100%{opacity:.3}30%{opacity:1}}
.caption{position:absolute;left:0;right:0;bottom:12px;text-align:center;font-size:.65rem;letter-spacing:.04em;color:var(--text-secondary)}
#cursor{position:absolute;left:0;top:0;width:22px;height:22px;z-index:50;pointer-events:none;transform:translate(1040px,610px);transition:transform 650ms cubic-bezier(.2,.7,.2,1)}
.ripple{position:absolute;z-index:49;width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:50%;border:2px solid var(--primary);pointer-events:none;animation:ripple 520ms ease-out forwards}
@keyframes ripple{to{transform:scale(3.2);opacity:0}}
.flash .transaction-list>:first-child{animation:rowflash 1.8s ease-out}
@keyframes rowflash{from{background:color-mix(in srgb,var(--primary) 22%,transparent)}to{background:transparent}}
.tx-panel h2{margin:0 0 6px}
.wf-title{position:absolute;left:40px;top:28px;font-size:.95rem;font-weight:600;letter-spacing:-.02em;color:var(--text-primary)}
.wf-title small{display:block;margin-top:4px;font-size:.7rem;font-weight:400;color:var(--text-secondary)}
`;

export default function Scenes(){
  const scene=typeof window==='undefined'?'connect':(new URLSearchParams(location.search).get('s')??'connect');
  const [msgs,setMsgs]=useState<Msg[]>([]);
  const [phoneMode,setPhoneMode]=useState<'start'|'input'>('input');
  const demo=useMemo(()=>demoState(),[]);
  const base=useMemo(()=>demo.transactions.filter(t=>t.date<=today()&&['expense','income'].includes(t.type)).sort((a,b)=>b.date.localeCompare(a.date)).slice(0,3),[demo]);
  const [added,setAdded]=useState<Transaction[]>([]);
  const [flash,setFlash]=useState(false);
  const [active,setActive]=useState<string[]>([]);

  const fetcher=useCallback(async(_:RequestInfo|URL,init?:RequestInit)=>{
    const w=window as W;
    if(init?.method==='POST')return Response.json({url:'https://t.me/exemplo_bot?start=tokenfalso',appUrl:'tg://resolve?domain=exemplo_bot&start=tokenfalso'});
    return Response.json(w.__linked?{linked:true,chatId:'123456789',accountId:'a1'}:{linked:false});
  },[]);

  useEffect(()=>{
    document.documentElement.classList.remove('light');document.documentElement.classList.add('dark');
    const w=window as W;
    document.addEventListener('click',e=>{const a=(e.target as HTMLElement).closest('a[target=_blank],a[href^="tg:"]');if(a)e.preventDefault()},true);
    let n=0;
    w.scene={
      reset(){setMsgs([]);setAdded([]);setActive([]);w.__linked=false;setPhoneMode(new URLSearchParams(location.search).get('s')==='connect'?'start':'input')},
      say(kind:Msg['kind'],text:string){setMsgs(m=>[...m.filter(x=>x.kind!=='typing'),{id:++n,kind,text}])},
      typing(on:boolean){setMsgs(m=>on?[...m.filter(x=>x.kind!=='typing'),{id:++n,kind:'typing',text:''}]:m.filter(x=>x.kind!=='typing'))},
      phone(mode:'start'|'input'){setPhoneMode(mode)},
      linked(v:boolean){w.__linked=v},
      addTx(description:string,amount:number,categoryId:string){
        setAdded(a=>[...a,{...baseTransaction(),type:'expense',description,amount,date:today(),accountId:'salary',categoryId}]);
        setFlash(false);requestAnimationFrame(()=>setFlash(true));
      },
      hl(names:string[]){setActive(names)},
      moveTo(sel:string,dx=0,dy=0){const el=document.querySelector(sel);if(!el)throw Error('sem elemento '+sel);const r=el.getBoundingClientRect();const c=document.getElementById('cursor')!;c.style.transform=`translate(${r.left+r.width/2+dx}px,${r.top+r.height/2+dy}px)`;return `${Math.round(r.left)},${Math.round(r.top)}`},
      click(){const c=document.getElementById('cursor')!;const m=/translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(c.style.transform)!;const r=document.createElement('div');r.className='ripple';r.style.left=m[1]+'px';r.style.top=m[2]+'px';c.parentElement!.appendChild(r);setTimeout(()=>r.remove(),700)},
    };
    document.fonts.ready.then(()=>{w.scene.reset();setTimeout(()=>{w.__ready=true},400)});
  },[]);

  const phone=<div className="phone-wrap"><figure className="telegram-phone" style={{margin:0}}><div className="telegram-phone-screen">
    <span className="telegram-phone-notch"/>
    <div className="telegram-phone-header"><span className="telegram-phone-avatar"><BrandSymbol/></span><span><b>CIFRO</b><small>bot</small></span></div>
    <div className="telegram-phone-chat">{msgs.map(m=>m.kind==='typing'
      ?<p key={m.id} className="telegram-bubble typing"><i/><i/><i/></p>
      :<p key={m.id} className={`telegram-bubble${m.kind==='me'?' telegram-sent':''}`}>{m.text}</p>)}</div>
    {phoneMode==='start'?<div className="start-bar" id="start-btn">INICIAR</div>:<div className="telegram-phone-input"><span>Mensagem</span><span className="telegram-phone-send"><Send size={13}/></span></div>}
  </div></figure></div>;

  const cursor=<><svg id="cursor" viewBox="0 0 24 24"><path d="M5 3l13 7-6 2-2 6z" fill="#fff" stroke="#0b1220" strokeWidth="1.4" strokeLinejoin="round"/></svg></>;

  if(scene==='workflow'){
    const act=new Set(active);
    const isOn=(a:string,b:string)=>act.has(a)&&act.has(b);
    return <div className="stage" style={{display:'block'}}><style>{css}</style>
      <div className="wf-title">Workflow do n8n<small>Cada mensagem percorre um destes caminhos</small></div>
      <svg width="1000" height="560" style={{position:'absolute',left:0,top:0}}>
        {edges.map(([a,b,o],i)=>{const A=pos(a),B=pos(b);const x1=A.x+NW,y1=A.y+NH/2,x2=B.x,y2=B.y+NH/2;const mx=(x1+x2)/2;const on=isOn(a,b)&&(o===0||a==='É conexão?'||a==='É despesa?');
          return <path key={i} d={`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`} fill="none" stroke={on?'var(--primary)':'var(--text-secondary)'} strokeOpacity={on?1:.35} strokeWidth={on?2.6:1.4} strokeDasharray={o===1?'5 4':undefined}/>})}
        {nodes.map(({n})=>{const p=pos(n);const on=act.has(n);const lines=wrap(n);
          return <g key={n}><rect x={p.x} y={p.y} width={NW} height={NH} rx={10} fill="var(--surface)" stroke={on?'var(--primary)':'var(--border)'} strokeWidth={on?2.4:1}/>
            {lines.map((l,i)=><text key={i} x={p.x+NW/2} y={p.y+NH/2+(i-(lines.length-1)/2)*13+4} textAnchor="middle" fontSize="11" fontWeight={on?600:500} fill={on?'var(--text-primary)':'var(--text-secondary)'}>{l}</text>)}</g>})}
      </svg>
      <div className="caption">Diagrama gerado a partir do workflow exportado · não é uma captura do n8n</div></div>;
  }

  return <div className={`stage${flash?' flash':''}`}><style>{css}</style>
    <div className="left">
      {scene==='connect'
        ?<TelegramLink accounts={accounts} authorizedFetch={fetcher} setConfirm={()=>{}}/>
        :<section className="panel tx-panel"><h2>Lançamentos</h2><TransactionRows items={[...base,...added]} state={demo} onSelect={()=>{}}/></section>}
    </div>
    {phone}
    {cursor}
    <div className="caption">Simulação com dados fictícios · interface do CIFRO</div>
  </div>;
}
