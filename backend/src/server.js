import {readFileSync} from 'node:fs';
import {Pool} from 'pg';
import {createApp} from './app.js';
import {Broker} from './broker.js';
const env=process.env;
for(const k of ['DATABASE_URL','AUTH_SECRET','SIGNING_KEY','MQTT_URL','MQTT_PUBLIC_HOST'])if(!env[k])throw Error(`Missing ${k}`);
if(env.AUTH_SECRET.length<32)throw Error('AUTH_SECRET must have at least 32 characters');
const db=new Pool({connectionString:env.DATABASE_URL});await db.query(readFileSync(new URL('./schema.sql',import.meta.url),'utf8'));
const broker=new Broker(env);
// Restore expiry enforcement after API restart, including credentials whose lease expired.
for(const s of (await db.query('SELECT broker_user,expires FROM sessions')).rows)broker.leases.set(s.broker_user,Number(s.expires));
await new Promise((resolve,reject)=>{if(broker.client.connected)return resolve();broker.client.once('connect',resolve);setTimeout(()=>reject(Error('Broker connection timeout')),15000).unref();});
try { await broker.command({command:'createRole',rolename:'api-robot-state',acls:[{acltype:'subscribePattern',topic:'airobot/v1/robots/+/state',allow:true},{acltype:'publishClientReceive',topic:'airobot/v1/robots/+/state',allow:true}]}); } catch(e) { if(!e.message.includes('already exists'))throw e; }
const admin=await broker.command({command:'getClient',username:env.MQTT_ADMIN_USER});
if(!admin.data.client.roles.some(r=>r.rolename==='api-robot-state'))await broker.command({command:'addClientRole',username:env.MQTT_ADMIN_USER,rolename:'api-robot-state',priority:10});
await broker.client.subscribeAsync('airobot/v1/robots/+/state',{qos:1});
const app=createApp({db,broker,key:readFileSync(env.SIGNING_KEY),secret:env.AUTH_SECRET});
const server=app.listen(Number(env.PORT||8080),env.BIND_ADDRESS||'127.0.0.1',()=>console.log('AiRobot API ready'));
process.on('SIGTERM',()=>server.close(async()=>{await broker.close();await db.end();}));
