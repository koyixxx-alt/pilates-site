/* デモ表示用（URLの末尾に ?demo を付けたときだけ読み込まれます）
   本物のデータベースには一切つながず、この画面の中だけで動くサンプルデータです。 */
(function(){
  const pad=n=>String(n).padStart(2,'0');
  const ymd=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
  const T=new Date();T.setHours(0,0,0,0);
  const day=o=>{const d=new Date(T);d.setDate(d.getDate()+o);return ymd(d);};
  let s=20261006;const rnd=()=>{s=(s*1664525+1013904223)%4294967296;return s/4294967296;};
  const pick=a=>a[Math.floor(rnd()*a.length)];
  let seq=1;const uid=()=>'demo-'+(seq++);

  const db={profiles:[{id:'demo-owner',role:'owner'}],customers:[],measurements:[],sessions:[],payments:[],proteins:[],reservations:[],products:[],plan_prices:[],
    studio_settings:[{id:1,studio_name:'Noailles',phone:'03-0000-0000',address:'東京都〇〇区〇〇 1-2-3',hours:'10:00〜21:00',holiday:'水曜日',coupon_every:3,coupon_amount:1000}]};
  const P1={id:uid(),name:'ソイプロテイン 500g',kind:'protein',price:4800,volume_g:500,serving_g:20,active:true,created_at:day(-500)};
  const P2={id:uid(),name:'ホエイプロテイン 500g',kind:'protein',price:5200,volume_g:500,serving_g:25,active:true,created_at:day(-499)};
  const B1={id:uid(),name:'美容ドリンク',kind:'other',price:3200,active:true,created_at:day(-498)};
  db.products.push(P1,P2,B1);

  const people=[['佐藤 美咲','さとう みさき',['training']],['高橋 由衣','たかはし ゆい',['slimming']],['中村 彩','なかむら あや',['bust','training']],
    ['伊藤 舞','いとう まい',['training']],['小林 さくら','こばやし さくら',['slimming']],['山本 恵','やまもと めぐみ',['bust']],
    ['渡辺 結衣','わたなべ ゆい',['training','slimming']],['加藤 葵','かとう あおい',['training']],['吉田 真由','よしだ まゆ',['slimming']]];
  const PRICE={training:12000,slimming:15000,bust:16000};
  people.forEach(([name,kana,cats],i)=>{
    const joined=day(-420+i*25);
    const bd=i===1?`1990-${day(8).slice(5)}`:`19${86+i}-${pad((i*4)%12+1)}-${pad(3+i*3)}`;
    const c={id:uid(),name,kana,email:`member${i+1}@example.com`,phone:`090-0000-00${pad(i)}`,birthday:bd,gender:'女性',joined,
      goal:['姿勢改善','体脂肪を5%減らす','産後の体型ケア','肩こり改善'][i%4],notes:null,address:'東京都〇〇区',
      cat_training:cats.includes('training'),cat_slimming:cats.includes('slimming'),cat_bust:cats.includes('bust'),
      price_training:PRICE.training,price_slimming:PRICE.slimming,price_bust:PRICE.bust,created_at:joined+'T10:00:00'};
    if(i===8){c.withdrawn_at=day(-60);c.withdraw_reason='引っ越し';}
    db.customers.push(c);
    cats.forEach(k=>db.plan_prices.push({id:uid(),customer_id:c.id,category:k,price:PRICE[k],effective_date:joined,created_at:joined}));
  });

  /* 過去の来店・会計・計測 */
  db.customers.forEach((c,i)=>{
    const cats=['training','slimming','bust'].filter(k=>c['cat_'+k]);
    let w=58+i*1.3,f=29-i*.4,waist=72+i;
    const end=c.withdrawn_at?-60:-1;
    let n=0;
    for(let o=-418+i*25;o<=end;o+=6+Math.floor(rnd()*4)){
      const date=day(o),k=cats[n%cats.length];n++;
      db.sessions.push({id:uid(),customer_id:c.id,date,category:k,menu:pick(['マットピラティス','骨盤調整','体幹トレーニング','ストレッチ']),duration:50,note:null,created_at:date+'T12:00:00'});
      if(n%3===1){w-=.25+rnd()*.3;f-=.15+rnd()*.2;waist-=.2;
        db.measurements.push({id:uid(),customer_id:c.id,date,weight:+w.toFixed(1),body_fat:+f.toFixed(1),waist:+waist.toFixed(1),hip:null,thigh:null,arm:null,note:null,created_at:date});}
      const lines=[{kind:k,name:({training:'トレーニング',slimming:'痩身',bust:'バスト'})[k]+'（契約料金）',price:PRICE[k],qty:1,product_id:null}];
      const buyP=(i%3!==2)&&n%4===0, buyB=n%7===0;
      if(buyP)lines.push({kind:'protein',name:P1.name,price:P1.price,qty:1,product_id:P1.id});
      if(buyB)lines.push({kind:'beauty',name:B1.name,price:B1.price,qty:1,product_id:B1.id});
      const sub=lines.reduce((a,l)=>a+l.price*l.qty,0);
      const pid=uid();
      db.payments.push({id:pid,customer_id:c.id,customer_name:c.name,date,amount:sub,category:k,categories:[...new Set(lines.map(l=>l.kind))],items:lines,
        subtotal:sub,adjust_amount:0,coupons_used:0,coupon_discount:0,method:pick(['cash','card','card','qr']),voided_at:null,created_at:date+'T13:00:00'});
      if(buyP)db.proteins.push({id:uid(),customer_id:c.id,purchase_date:date,product_id:P1.id,volume_g:500,serving_g:20,per_day:1,payment_id:pid,created_at:date});
    }
  });
  /* 割引券を使った会計を1件・取り消した会計を1件 */
  const p0=db.payments.filter(p=>p.customer_id===db.customers[0].id).slice(-3)[0];
  if(p0){p0.coupons_used=1;p0.coupon_discount=1000;p0.amount-=1000;}
  const pv=db.payments.filter(p=>p.date===day(-2))[0]||db.payments[db.payments.length-5];
  if(pv){pv.voided_at=day(-2)+'T18:00:00';pv.void_reason='金額の入力ミス';}

  /* 今日・この先の予約 */
  const C=db.customers;
  const r1={id:uid(),customer_id:C[0].id,date:day(0),time:'10:00',category:'training',duration:50,status:'booked',checked_in_at:day(0)+'T09:55:00'};
  const r2={id:uid(),customer_id:C[1].id,date:day(0),time:'13:30',category:'slimming',duration:50,status:'booked',checked_in_at:day(0)+'T13:25:00'};
  const r3={id:uid(),customer_id:C[2].id,date:day(0),time:'18:00',category:'bust',duration:50,status:'booked',checked_in_at:null};
  db.reservations.push(r1,r2,r3);
  db.sessions.push({id:uid(),customer_id:C[0].id,date:day(0),category:'training',menu:'マットピラティス',duration:50,note:'骨盤の動きが良くなってきた',reservation_id:r1.id,created_at:day(0)+'T10:55:00'});
  db.payments.push({id:uid(),customer_id:C[0].id,customer_name:C[0].name,date:day(0),amount:12000,category:'training',categories:['training'],
    items:[{kind:'training',name:'トレーニング（契約料金）',price:12000,qty:1,product_id:null}],subtotal:12000,adjust_amount:0,coupons_used:0,coupon_discount:0,method:'card',reservation_id:r1.id,created_at:day(0)+'T11:00:00'});
  [[1,3,'11:00','training'],[2,0,'10:00','training'],[2,4,'15:00','slimming'],[4,5,'13:00','bust'],[6,1,'19:00','slimming'],[7,6,'10:30','training']]
    .forEach(([o,ci,t,k])=>db.reservations.push({id:uid(),customer_id:C[ci].id,date:day(o),time:t,category:k,duration:50,status:'booked',checked_in_at:null}));
  /* 中村 彩さんはスタンプ3個で割引券あり */
  const c2=C[2];const extra=db.payments.filter(p=>p.customer_id===c2.id).slice(-3);
  extra.forEach(p=>{if(!p.items.some(l=>l.kind==='protein')){p.items.push({kind:'protein',name:P1.name,price:P1.price,qty:1,product_id:P1.id});p.subtotal+=P1.price;p.amount+=P1.price;p.categories=[...new Set(p.items.map(l=>l.kind))];
    db.proteins.push({id:uid(),customer_id:c2.id,purchase_date:p.date,product_id:P1.id,volume_g:500,serving_g:20,per_day:1,payment_id:p.id,created_at:p.date});}});

  /* ---- Supabase の代わりに動く最小限のクライアント ---- */
  const clone=o=>JSON.parse(JSON.stringify(o));
  function query(table){
    const st={op:'select',payload:null,filters:[],order:null,single:false,ret:false};
    const b={
      select(){if(st.op!=='select')st.ret=true;return b;},
      order(col,o){st.order={col,asc:!(o&&o.ascending===false)};return b;},
      eq(col,v){st.filters.push([col,v]);return b;},
      insert(p){st.op='insert';st.payload=p;return b;},
      update(p){st.op='update';st.payload=p;return b;},
      delete(){st.op='delete';return b;},
      single(){st.single=true;return b;},
      maybeSingle(){st.single=true;return b;},
      then(ok,ng){return Promise.resolve(run()).then(ok,ng);}
    };
    function rows(){return db[table]||(db[table]=[]);}
    function match(r){return st.filters.every(([c,v])=>String(r[c])===String(v));}
    function run(){
      if(!(table in db))return {data:null,error:{message:`relation "${table}" does not exist`}};
      if(st.op==='select'){let out=rows().filter(match);
        if(st.order){const {col,asc}=st.order;out=out.slice().sort((a,b)=>String(a[col]??'').localeCompare(String(b[col]??''))*(asc?1:-1));}
        out=clone(out);return {data:st.single?(out[0]||null):out,error:null};}
      if(st.op==='insert'){const list=(Array.isArray(st.payload)?st.payload:[st.payload]).map(p=>Object.assign({id:uid(),created_at:new Date().toISOString()},clone(p)));
        if(table==='payments')list.forEach(p=>{if(p.voided_at===undefined)p.voided_at=null;});
        rows().push(...list);return {data:st.single?clone(list[0]):clone(list),error:null};}
      if(st.op==='update'){rows().filter(match).forEach(r=>Object.assign(r,clone(st.payload)));return {data:null,error:null};}
      if(st.op==='delete'){const keep=rows().filter(r=>!match(r));const gone=rows().filter(match).map(r=>r.id);db[table]=keep;
        if(table==='customers'){['measurements','sessions','proteins','reservations','plan_prices'].forEach(t=>db[t]=db[t].filter(r=>!gone.includes(r.customer_id)));
          db.payments.forEach(p=>{if(gone.includes(p.customer_id))p.customer_id=null;});}
        return {data:null,error:null};}
    }
    return b;
  }
  window.demoClient={
    from:query,
    rpc:async n=>({data:n==='am_i_owner'?true:n==='am_i_admin'?false:null,error:null}),
    auth:{
      getSession:async()=>({data:{session:{user:{id:'demo-owner'}}}}),
      getUser:async()=>({data:{user:{id:'demo-owner',email:'demo@noailles.example'}}}),
      signInWithPassword:async()=>({error:null}),signOut:async()=>({error:null}),
      updateUser:async()=>({error:null}),onAuthStateChange(){}
    }
  };
})();
