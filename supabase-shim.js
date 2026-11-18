/* Firebase-compatible shim: Store app ka data ab Supabase (store_state table) mein save hota hai. */
(function(){
 const C=window.DIK_CONFIG,sb=window.supabase.createClient(C.SUPABASE_URL,C.SUPABASE_ANON_KEY);
 const CID=Math.random().toString(36).slice(2),T='store_state';
 const need=async()=>{const {data}=await sb.auth.getSession();if(!data.session){document.body.innerHTML='<p style="padding:24px;font:16px system-ui">Pehle Main System se login karen.</p>';throw new Error('no session')}};
 const snap=v=>({val:()=>v});
 function ref(path){
  const key=path.replace(/\//g,':'),tree=path==='dus_store_backups';
  const r={
   async once(){await need();
    if(tree){const {data,error}=await sb.from(T).select('key,data').like('key','dus_store_backups:%');if(error)throw error;const o={};(data||[]).forEach(x=>o[x.key.split(':')[1]]=x.data);return snap(Object.keys(o).length?o:null)}
    const {data,error}=await sb.from(T).select('data').eq('key',key).maybeSingle();if(error)throw error;return snap(data?data.data:null)},
   async set(v){await need();const {error}=await sb.from(T).upsert({key,data:JSON.parse(JSON.stringify(v)),updated_at:new Date().toISOString(),client:CID});
    if(key==='dus_store'){try{SUPPRESS_NEXT_REMOTE=false}catch(e){}}if(error)throw error},
   async remove(){await need();await sb.from(T).delete().eq('key',key)},
   on(ev,cb){if(path==='.info/connected'){cb(snap(true));return}
    (async()=>{await need();cb(await r.once());
     sb.channel('st_'+key).on('postgres_changes',{event:'*',schema:'public',table:T,filter:'key=eq.'+key},p=>{if(p.new&&p.new.client===CID)return;cb(snap(p.new?p.new.data:null))}).subscribe()})()}
  };return r}
 window.firebaseConfig={apiKey:'supabase'};
 window.firebase={initializeApp(){},database:()=>({ref})};
})();
