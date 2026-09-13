import express from 'express';
import {random,hash,passwordHash,passwordValid,accessToken,identity,signGrant} from './security.js';
import {profileValid,programValid} from './validation.js';
export function createApp({db,broker,key,secret,now=Date.now}){
 const app=express();app.disable('x-powered-by');app.use(express.json({limit:'64kb'}));
 const auth=(req,res,next)=>{try{req.user=identity(req.headers.authorization?.replace(/^Bearer /,''),secret,now());next();}catch{res.status(401).json({error:'unauthorized'});}};
 const route=fn=>async(req,res,next)=>{try{await fn(req,res);}catch(e){next(e);}};
 const owned=async(id,user)=>{let r=await db.query('SELECT * FROM robots WHERE id=$1 AND owner_id=$2',[id,user]);if(!r.rowCount)throw Object.assign(Error('robot-not-found'),{status:404});return r.rows[0];};
 const latest=async id=>(await db.query('SELECT * FROM profiles WHERE robot_id=$1 ORDER BY version DESC LIMIT 1',[id])).rows[0];
 // Bounded per-address authentication throttle; proxy must preserve actual peers.
 const attempts=new Map();app.use('/auth',(req,res,next)=>{let k=req.ip,t=now(),v=attempts.get(k);if(!v||t-v.start>60000)v={start:t,count:0};v.count++;attempts.set(k,v);if(attempts.size>10000)attempts.delete(attempts.keys().next().value);if(v.count>20)return res.status(429).json({error:'try-later'});next();});
 app.get('/health',(_,res)=>res.json({ok:true}));
 app.post('/auth/register',route(async(req,res)=>{let {email,password}=req.body;if(typeof email!=='string'||!/^\S+@\S+\.\S+$/.test(email)||email.length>254)return res.status(400).json({error:'email'});let stored;try{stored=passwordHash(password);}catch{return res.status(400).json({error:'password-minimum-12'});}let id=random();await db.query('INSERT INTO users(id,email,password) VALUES($1,$2,$3)',[id,email.toLowerCase(),stored]);res.status(201).json({token:accessToken(id,secret,now())});}));
 app.post('/auth/login',route(async(req,res)=>{let {email,password}=req.body;let u=(await db.query('SELECT * FROM users WHERE email=$1',[typeof email==='string'?email.toLowerCase():''])).rows[0];if(!u||!passwordValid(password,u.password))return res.status(401).json({error:'invalid-login'});res.json({token:accessToken(u.id,secret,now())});}));
 app.use(auth);
 app.get('/robots',route(async(req,res)=>res.json((await db.query('SELECT id FROM robots WHERE owner_id=$1',[req.user])).rows)));
 app.post('/pair',route(async(req,res)=>{const {robotId,token}=req.body;if(typeof robotId!=='string'||typeof token!=='string')return res.status(400).json({error:'pairing'});let r=await db.query('UPDATE robots SET owner_id=$1,pairing_hash=NULL,pairing_expires=NULL WHERE id=$2 AND owner_id IS NULL AND pairing_hash=$3 AND pairing_expires>$4 RETURNING id',[req.user,robotId,hash(token),now()]);if(!r.rowCount)return res.status(409).json({error:'pairing-unavailable'});res.json(r.rows[0]);}));
 app.get('/robots/:id/profile',route(async(req,res)=>{await owned(req.params.id,req.user);let p=await latest(req.params.id);if(!p)return res.status(404).json({error:'no-profile'});res.json({profileJson:p.body,profileHash:p.hash});}));
 app.post('/robots/:id/profile',route(async(req,res)=>{await owned(req.params.id,req.user);const p=req.body;if(!profileValid(p))return res.status(400).json({error:'invalid-profile'});let previous=await latest(req.params.id);if(previous&&p.version!==previous.version+1||!previous&&p.version!==1)return res.status(409).json({error:'profile-version'});const body=JSON.stringify(p),digest=hash(body);await db.query('INSERT INTO profiles(robot_id,version,hash,body) VALUES($1,$2,$3,$4)',[req.params.id,p.version,digest,body]);res.status(201).json({profileJson:body,profileHash:digest});}));
 app.get('/robots/:id/programs',route(async(req,res)=>{await owned(req.params.id,req.user);const profile=await latest(req.params.id);let result=(await db.query('SELECT * FROM programs WHERE robot_id=$1',[req.params.id])).rows;res.json(result.map(p=>({...p,needsRevalidation:p.body.profileHash!==profile?.hash})));}));
 app.post('/robots/:id/programs',route(async(req,res)=>{await owned(req.params.id,req.user);let {name,body,sourceId}=req.body,profile=await latest(req.params.id);if(typeof name!=='string'||!name.trim()||name.length>100||!programValid(body))return res.status(400).json({error:'invalid-program'});if(!profile||profile.hash!==body.profileHash||profile.version!==body.profileVersion||JSON.parse(profile.body).homeRevision!==body.homeRevision)return res.status(409).json({error:'profile-mismatch'});let id=random(),family=id,revision=1;if(sourceId){const source=(await db.query('SELECT * FROM programs WHERE id=$1 AND robot_id=$2',[sourceId,req.params.id])).rows[0];if(!source)return res.status(404).json({error:'program-not-found'});family=source.family_id||source.id;const last=(await db.query('SELECT revision FROM programs WHERE family_id=$1 ORDER BY revision DESC LIMIT 1',[family])).rows[0];revision=(last?.revision||source.revision)+1;}await db.query('INSERT INTO programs(id,robot_id,name,revision,family_id,body) VALUES($1,$2,$3,$4,$5,$6)',[id,req.params.id,name,revision,family,body]);res.status(201).json({id,revision});}));
 app.delete('/robots/:id/programs/:program',route(async(req,res)=>{await owned(req.params.id,req.user);await db.query('DELETE FROM programs WHERE id=$1 AND robot_id=$2',[req.params.program,req.params.id]);res.json({ok:true});}));
 app.get('/robots/:id/state',route(async(req,res)=>{await owned(req.params.id,req.user);let status=broker.states.get(req.params.id);if(!status||now()-status.receivedAt>5000)return res.status(409).json({error:'robot-offline'});res.json(status);}));
 app.post('/robots/:id/session',route(async(req,res)=>{
  await owned(req.params.id,req.user);let {bootId,scope='control',sessionId}=req.body;if(typeof bootId!=='string'||bootId.length>64||!['control','recovery'].includes(scope))return res.status(400).json({error:'session'});
  const id=req.params.id;const status=broker.states.get(id);if(!status||status.bootId!==bootId||now()-status.receivedAt>5000)return res.status(409).json({error:'robot-state-stale'});
  // Conditional upsert grants an exclusive lease, including competing devices of the same owner.
  const candidate=random(),expires=now()+15000,brokerUser='app-'+candidate,brokerPassword=random();
  const existing=(await db.query('SELECT * FROM sessions WHERE robot_id=$1',[id])).rows[0];
  if(existing&&Number(existing.expires)>now()){
   if(sessionId!==existing.id||existing.user_id!==req.user||existing.boot_id!==bootId||existing.scope!==scope)return res.status(409).json({error:'control-busy'});
   await db.query('UPDATE sessions SET expires=$1 WHERE robot_id=$2 AND id=$3',[expires,id,existing.id]);
   await broker.extend(existing.broker_user,expires);
   return res.json(reply(existing,expires));
  }
  if(sessionId)return res.status(409).json({error:'session-expired-reconnect'});
  const r=await db.query('INSERT INTO sessions(robot_id,id,user_id,boot_id,scope,expires,broker_user,broker_password) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(robot_id) DO UPDATE SET id=EXCLUDED.id,user_id=EXCLUDED.user_id,boot_id=EXCLUDED.boot_id,scope=EXCLUDED.scope,expires=EXCLUDED.expires,broker_user=EXCLUDED.broker_user,broker_password=EXCLUDED.broker_password WHERE sessions.expires<=$9 RETURNING *',[id,candidate,req.user,bootId,scope,expires,brokerUser,brokerPassword,now()]);
  if(!r.rowCount)return res.status(409).json({error:'control-busy'});const s=r.rows[0];
  try{await broker.grant(brokerUser,brokerPassword,id,expires);}catch(e){await db.query('DELETE FROM sessions WHERE robot_id=$1 AND id=$2',[id,candidate]);throw e;}
  res.json(reply(s,expires));
  function reply(s,until){return {sessionId:s.id,expiresAtEpochMs:until,authorization:signGrant({robotId:id,bootId,sessionId:s.id,sub:req.user,scope,expiresAtEpochMs:until},key),mqtt:{...broker.publicEndpoint,username:s.broker_user,password:s.broker_password}};}
 }));
 app.delete('/robots/:id/session',route(async(req,res)=>{await owned(req.params.id,req.user);let r=await db.query('DELETE FROM sessions WHERE robot_id=$1 AND user_id=$2 RETURNING broker_user',[req.params.id,req.user]);for(let s of r.rows)await broker.revoke(s.broker_user);res.json({ok:true});}));
 app.use((e,req,res,next)=>{res.status(e.status|| (e.code==='23505'?409:500)).json({error:e.status?e.message:e.code==='23505'?'conflict':'server-error'});});return app;
}
