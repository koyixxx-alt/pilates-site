/* デモ表示用（URLの末尾に ?demo を付けたときだけ読み込まれます）。本物のデータには接続しません。 */
(function(){
  const pad=n=>String(n).padStart(2,'0');
  const ymd=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
  const T=new Date();T.setHours(0,0,0,0);
  const day=o=>{const d=new Date(T);d.setDate(d.getDate()+o);return ymd(d);};
  let seq=1;const uid=()=>'demo-'+(seq++);
  const me={id:'demo-me',name:'佐藤 美咲',kana:'さとう みさき',email:'member1@example.com',goal:'姿勢改善と体脂肪-5%',joined:day(-300),
    cat_training:true,cat_slimming:false,cat_bust:false,withdrawn_at:null};
  const db={customers:[me],measurements:[],sessions:[],
    studio_settings:[{id:1,studio_name:'Noailles',phone:'03-0000-0000',address:'東京都〇〇区〇〇 1-2-3',hours:'10:00〜21:00',holiday:'水曜日',coupon_every:3,coupon_amount:1000}]};
  let w=58.6,f=28.4,waist=72.5,n=0;
  const menus=['マットピラティス','骨盤調整','体幹トレーニング','ストレッチ'];
  const notes=['骨盤の動きが良くなってきました。次回は呼吸を意識しましょう。',null,'肩の力が抜けてきています。お家でもキャットストレッチを。',null];
  for(let o=-290;o<=-1;o+=7){
    const date=day(o);n++;
    db.sessions.push({id:uid(),customer_id:me.id,date,category:'training',menu:menus[n%4],duration:50,note:notes[n%4]});
    if(n%3===1){w-=.35;f-=.25;waist-=.3;db.measurements.push({id:uid(),customer_id:me.id,date,weight:+w.toFixed(1),body_fat:+f.toFixed(1),waist:+waist.toFixed(1),hip:null,thigh:null,arm:null,note:null});}
  }
  const rpcs={
    my_reservations:[{date:day(2),time:'10:00',category:'training',duration:50},{date:day(9),time:'10:00',category:'training',duration:50},{date:day(16),time:'10:00',category:'training',duration:50}],
    my_coupon_status:{qty:8,used:1,every:3,amount:1000}
  };
  const clone=o=>JSON.parse(JSON.stringify(o));
  function query(table){
    const st={op:'select',payload:null,filters:[],order:null,single:false};
    const b={select(){return b;},order(c,o){st.order={c,asc:!(o&&o.ascending===false)};return b;},eq(c,v){st.filters.push([c,v]);return b;},
      insert(p){st.op='insert';st.payload=p;return b;},single(){st.single=true;return b;},maybeSingle(){st.single=true;return b;},
      then(ok,ng){return Promise.resolve(run()).then(ok,ng);}};
    function run(){
      const rows=db[table]||[];
      if(st.op==='insert'){rows.push(Object.assign({id:uid()},clone(st.payload)));return {data:null,error:null};}
      let out=rows.filter(r=>st.filters.every(([c,v])=>String(r[c])===String(v)));
      if(st.order){const {c,asc}=st.order;out=out.slice().sort((a,b)=>String(a[c]).localeCompare(String(b[c]))*(asc?1:-1));}
      out=clone(out);return {data:st.single?(out[0]||null):out,error:null};
    }
    return b;
  }
  window.demoClient={from:query,rpc:async n=>({data:clone(rpcs[n]??null),error:null}),
    auth:{getSession:async()=>({data:{session:{}}}),getUser:async()=>({data:{user:{id:'demo-me',email:me.email}}}),
      signInWithPassword:async()=>({error:null}),signUp:async()=>({data:{session:{}},error:null}),signOut:async()=>({error:null}),onAuthStateChange(){}}};
})();
