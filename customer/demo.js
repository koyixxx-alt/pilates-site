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
    studio_settings:[{id:1,studio_name:'Noailles',phone:'03-0000-0000',address:'東京都〇〇区〇〇 1-2-3',hours:'10:00〜21:00',holiday:'水曜日',coupon_every:3,coupon_amount:1000,
      booking_enabled:true,open_time:'10:00',close_time:'21:00',lesson_minutes:50,slot_step:30,closed_days:[3],book_days_ahead:30,book_min_hours:3,cancel_min_hours:24}]};
  let w=58.6,f=28.4,waist=72.5,n=0;
  const menus=['マットピラティス','骨盤調整','体幹トレーニング','ストレッチ'];
  const notes=['骨盤の動きが良くなってきました。次回は呼吸を意識しましょう。',null,'肩の力が抜けてきています。お家でもキャットストレッチを。',null];
  for(let o=-290;o<=-1;o+=7){
    const date=day(o);n++;
    db.sessions.push({id:uid(),customer_id:me.id,date,category:'training',menu:menus[n%4],duration:50,note:notes[n%4]});
    if(n%3===1){w-=.35;f-=.25;waist-=.3;db.measurements.push({id:uid(),customer_id:me.id,date,weight:+w.toFixed(1),body_fat:+f.toFixed(1),waist:+waist.toFixed(1),hip:null,thigh:null,arm:null,note:null});}
  }
  const mine=[{id:uid(),date:day(2),time:'10:00',category:'training',duration:50,status:'booked'},{id:uid(),date:day(9),time:'10:00',category:'training',duration:50,status:'booked'}];
  const others=[[1,'11:00'],[1,'15:00'],[2,'13:00'],[3,'10:00'],[3,'18:30'],[4,'19:00']].map(([o,t])=>({date:day(o),time:t,duration:50}));
  const rpcs={
    my_reservations:()=>mine.slice().sort((a,b)=>(a.date+a.time).localeCompare(b.date+b.time)),
    my_coupon_status:()=>({qty:8,used:1,every:3,amount:1000}),
    busy_slots:()=>others.concat(mine.map(r=>({date:r.date,time:r.time,duration:r.duration}))),
    book_reservation:a=>{mine.push({id:uid(),date:a.p_date,time:a.p_time,category:a.p_category,duration:50,status:'booked'});return null;},
    cancel_my_reservation:a=>{const i=mine.findIndex(r=>r.id===a.p_id);if(i>=0)mine.splice(i,1);return null;}
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
  window.demoClient={from:query,rpc:async(n,a)=>({data:rpcs[n]?clone(rpcs[n](a||{})):null,error:null}),
    auth:{getSession:async()=>({data:{session:{}}}),getUser:async()=>({data:{user:{id:'demo-me',email:me.email}}}),
      signInWithPassword:async()=>({error:null}),signUp:async()=>({data:{session:{}},error:null}),signOut:async()=>({error:null}),onAuthStateChange(){}}};
})();
