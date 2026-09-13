#pragma once
#include "core.hpp"
#include <ArduinoJson.h>
#include <functional>
namespace airobot {
using Json=ArduinoJson::JsonDocument;
inline bool number(JsonVariantConst v){return v.is<double>()&&finite(v.as<double>());}
inline bool integer(JsonVariantConst v,int64_t lo,int64_t hi){return v.is<int64_t>()&&v.as<int64_t>()>=lo&&v.as<int64_t>()<=hi;}
inline bool textField(JsonVariantConst v,size_t max=128){return v.is<const char*>()&&strlen(v.as<const char*>())>0&&strlen(v.as<const char*>())<=max;}
template<size_t N> bool arrayNumber(JsonVariantConst v,std::array<double,N>&a){if(!v.is<JsonArrayConst>()||v.size()!=N)return false;for(size_t i=0;i<N;i++){if(!number(v[i]))return false;a[i]=v[i].as<double>();}return true;}
inline bool parseProfile(JsonVariantConst v,Profile&p){if(!v.is<JsonObjectConst>()||v.size()!=20)return false; // exact shape is checked again below
 if(!integer(v["version"],1,2147483647)||!integer(v["homeRevision"],1,2147483647)||v["kinematicsVersion"]!="ik-dls-1"||!v["calibrated"].is<bool>()||!v["geometryValidated"].is<bool>()||!v["simulationOnly"].is<bool>()||!integer(v["heartbeatMs"],100,10000)||!integer(v["maxTickMs"],20,100)||v["sda"]!=6||v["scl"]!=7||!number(v["linkRadius"]))return false;
 p.version=v["version"];p.homeRevision=v["homeRevision"];p.calibrated=v["calibrated"];p.geometryValidated=v["geometryValidated"];p.simulationOnly=v["simulationOnly"];p.heartbeatMs=v["heartbeatMs"];p.maxTickMs=v["maxTickMs"];p.sda=6;p.scl=7;p.linkRadius=v["linkRadius"];
 if(!arrayNumber(v["minimum"],p.minimum)||!arrayNumber(v["maximum"],p.maximum)||!arrayNumber(v["home"],p.home)||!arrayNumber(v["velocity"],p.velocity)||!arrayNumber(v["acceleration"],p.acceleration)||!arrayNumber(v["tool"],p.tool)||!v["servos"].is<JsonArrayConst>()||v["servos"].size()!=8||!v["axes"].is<JsonArrayConst>()||v["axes"].size()!=6||!v["boxes"].is<JsonArrayConst>()||v["boxes"].size()>8)return false;
 for(int i=0;i<8;i++){auto s=v["servos"][i];if(s.size()!=9||!integer(s["joint"],0,6)||!integer(s["pcaChannel"],0,15))return false;for(auto k:{"zero","offset","ratio","min","max","pulseMin","pulseMax"})if(!number(s[k]))return false;p.servos[i]={s["joint"],s["pcaChannel"],s["zero"],s["offset"],s["ratio"],s["min"],s["max"],s["pulseMin"],s["pulseMax"]};}
 for(int i=0;i<6;i++)if(v["axes"][i].size()!=2||!arrayNumber(v["axes"][i]["origin"],p.axes[i].origin)||!arrayNumber(v["axes"][i]["axis"],p.axes[i].axis))return false;
 p.boxes.clear();for(auto b:v["boxes"].as<JsonArrayConst>()){Box box;if(b.size()!=2||!arrayNumber(b["min"],box.min)||!arrayNumber(b["max"],box.max))return false;p.boxes.push_back(box);}return p.valid();
}
struct Runtime {
 Core core;Replay replay;std::string robotId,bootId,latchId,resetNonce,session,scope,profileJson;uint64_t sessionExpiry=0;bool simulation=true,hardwareReady=false,faultActive=false;
 std::function<std::string(const std::string&)> sha;
 std::function<std::string()> random;
 std::function<uint64_t()> clock;
 std::function<bool(const std::string&,Json&)> verify;
 std::function<bool(const std::string&,const std::string&)> persist;
 Runtime(std::string robot,std::string boot):robotId(robot),bootId(boot){}
 void invalidate(){session.clear();sessionExpiry=0;replay.open("");}
 bool authorized(JsonVariantConst c,Json&claims,uint64_t epoch,bool emergency){if(!textField(c["authorization"],2048)||!verify(c["authorization"].as<std::string>(),claims))return false;auto g=claims.as<JsonVariantConst>();if(g["robotId"]!=robotId||g["bootId"]!=bootId||!textField(g["sessionId"])||!textField(g["sub"])||!integer(g["expiresAtEpochMs"],1,9007199254740991LL)||(g["scope"]!="control"&&g["scope"]!="recovery"))return false;if(!emergency&&(epoch<1700000000000ULL||g["expiresAtEpochMs"].as<uint64_t>()<=epoch||g["expiresAtEpochMs"].as<uint64_t>()>epoch+20000))return false;return true;}
 std::string trackedExecution;
 bool lifecycle(Json&event){
  if(core.state==State::EXECUTING){if(core.activeId!=trackedExecution){trackedExecution=core.activeId;event["commandId"]=trackedExecution;event["status"]="started";return true;}return false;}
  if(trackedExecution.empty())return false;
  event["commandId"]=trackedExecution;event["status"]=(core.state==State::READY&&core.reason=="completed")?"completed":"cancelled";event["reason"]=core.reason;event["profileHash"]=core.profile.hash;replay.result(trackedExecution,event["status"].as<std::string>());trackedExecution.clear();return true;
 }
 Json status()const {Json s;s["schemaVersion"]=1;s["robotId"]=robotId;s["bootId"]=bootId;s["state"]=name(core.state);s["reason"]=core.reason;s["referenceValid"]=core.referenced;s["outputKnown"]=core.outputKnown;s["positionSource"]="commanded";s["simulation"]=simulation;s["actuatorsEnabled"]=!simulation&&hardwareReady&&core.referenced;s["profileVersion"]=core.profile.version;s["profileHash"]=core.profile.hash;s["latchId"]=latchId;s["resetNonce"]=resetNonce;s["activeCommandId"]=core.activeId;for(double q:core.q)s["targetJointDegrees"].add(q);if(core.referenced&&core.profile.geometryValidated){auto tcp=sub(forward(core.profile,core.q).position,forward(core.profile,core.profile.home).position);for(double x:tcp)s["estimatedTcpMm"].add(x);}else s["estimatedTcpMm"]=nullptr;s["capabilities"]["kinematicsVersion"]="ik-dls-1";s["capabilities"]["maxMessageBytes"]=16384;s["capabilities"]["maxSteps"]=32;s["capabilities"]["maxPauseMs"]=600000;s["capabilities"]["maxTtlMs"]=5000;s["capabilities"]["heartbeatMs"]=core.profile.heartbeatMs;return s;}
 Json handle(const std::string&raw,bool retained,uint64_t epoch,uint64_t mono,bool emergencyTopic=false){Json ack,c,claims;ack["status"]="rejected";auto reject=[&](const char*r){ack["reason"]=r;return ack;};if(retained)return reject("retained");if(raw.size()>16384||deserializeJson(c,raw)||!c.is<JsonObject>())return reject("schema");if(textField(c["commandId"],64))ack["commandId"]=c["commandId"];
  if(c["schemaVersion"]!=1||c["robotId"]!=robotId||c["bootId"]!=bootId||!textField(c["type"],32)||!textField(c["commandId"],64)||!authorized(c,claims,epoch,emergencyTopic))return reject("unauthorized-or-envelope");auto type=c["type"].as<std::string>();
  if(emergencyTopic){if(type!="emergencyStop")return reject("emergency-only");if(core.state!=State::ESTOP_LATCHED){core.latch();latchId=random();resetNonce=random();invalidate();if(!persist("latch",latchId)){faultActive=true;core.reason="latch-storage";}}ack["status"]="accepted";return ack;}
  if(type=="emergencyStop")return reject("use-emergency-topic");
  if(!integer(c["createdAtEpochMs"],1,9007199254740991LL)||!integer(c["expiresAtEpochMs"],1,9007199254740991LL))return reject("expiry");uint64_t created=c["createdAtEpochMs"],expires=c["expiresAtEpochMs"];if(created>epoch+1000||expires<=epoch||expires<created||expires-created>5000)return reject("expiry");
  std::string grantSession=claims["sessionId"],grantScope=claims["scope"];if(c["controlSessionId"]!=grantSession||!integer(c["sequence"],1,9007199254740991LL))return reject("session");
  if(type=="openSession"){if(!session.empty()&&session!=grantSession&&sessionExpiry>epoch)return reject("control-busy");if(session!=grantSession){session=grantSession;scope=grantScope;replay.open(session);}sessionExpiry=claims["expiresAtEpochMs"];core.beat(mono);}
  if(session!=grantSession)return reject("session-not-open");sessionExpiry=claims["expiresAtEpochMs"];auto id=c["commandId"].as<std::string>();auto digest=sha(raw);auto decision=replay.accept(id,c["sequence"],digest);if(decision!="ok"){ack["reason"]=decision;ack["status"]=decision.find("duplicate:")==0?"duplicate":"rejected";return ack;}
  auto finish=[&](bool ok,const char*r){ack["status"]=ok?"accepted":"rejected";ack["reason"]=r;ack["profileHash"]=core.profile.hash;replay.result(id,ok?"accepted":r);return ack;};
  if(type=="openSession"||type=="heartbeat"){core.beat(mono);return finish(true,"session-active");}
  if(type=="resetLatch"){if(scope!="recovery"||faultActive||c["payload"]["latchId"]!=latchId||c["payload"]["resetNonce"]!=resetNonce||resetNonce.empty()||(core.state!=State::ESTOP_LATCHED&&core.state!=State::FAULT))return finish(false,"reset-denied");if(!persist("latch","")){faultActive=true;return finish(false,"storage");}core.reset();latchId.clear();resetNonce.clear();invalidate();return finish(true,"reset-awaiting-reference");}
  if(type=="activateProfile"){if(core.state==State::EXECUTING||core.state==State::STOPPING||core.state==State::CALIBRATING)return finish(false,"busy");if(!textField(c["payload"]["profileJson"],12000)||!textField(c["payload"]["profileHash"],64))return finish(false,"profile-schema");std::string body=c["payload"]["profileJson"],h=c["payload"]["profileHash"];Json doc;Profile p;p.hash=h;if(sha(body)!=h||deserializeJson(doc,body)||!parseProfile(doc,p)||(!simulation&&p.simulationOnly))return finish(false,"profile-invalid");if(p.version<=core.profile.version)return finish(false,"profile-version");if(!persist("profile",body))return finish(false,"storage");core.configure(p);profileJson=body;invalidate();return finish(true,"profile-activated");}
  if(scope!="control")return finish(false,"recovery-only");if(c["profileVersion"]!=core.profile.version||c["profileHash"]!=core.profile.hash||c["kinematicsVersion"]!="ik-dls-1")return finish(false,"profile-mismatch");auto payload=c["payload"];
  if(type=="confirmReference"){Joints q{};if(!simulation&&!hardwareReady)return finish(false,"hardware-unavailable");return finish(arrayNumber(payload["jointDegrees"],q)&&payload["operatorConfirmed"]==true&&core.reference(q),"reference");}
  if(type=="enable")return finish(core.enable(mono),"enable");
  if(type=="acknowledgeHold"){core.beat(mono);return finish(core.acknowledge(),"hold");}
  if(type=="stop"){core.stop(mono,"operator-stop");return finish(true,"stop-requested");}
  if(core.state!=State::READY)return finish(false,"not-ready");std::vector<Step> steps;int speed=payload["speedPercent"]|0;
  if(type=="moveJoint"||type=="goHome"){if(!integer(payload["speedPercent"],1,100))return finish(false,"speed");auto q=type=="goHome"?core.profile.home:core.q;if(type=="moveJoint"){if(!integer(payload["joint"],0,6)||!number(payload["degrees"]))return finish(false,"joint-schema");q[payload["joint"].as<int>()]=payload["degrees"];}steps.push_back({q,speed,0});}
  else if(type=="moveTcp"||type=="runProgram"){if(!core.profile.geometryValidated)return finish(false,"geometry-unvalidated");Json single;if(type=="moveTcp")single["steps"].add(payload);JsonVariantConst list=type=="moveTcp"?single["steps"].as<JsonVariantConst>():payload["steps"].as<JsonVariantConst>();if(!list.is<JsonArrayConst>()||list.size()<1||list.size()>32||payload["orientation"]!="home"||(type=="runProgram"&&(payload["homeRevision"]!=core.profile.homeRevision||payload["profileHash"]!=core.profile.hash||payload["confirmed"]!=true)))return finish(false,"program-schema");auto from=core.q;for(auto s:list.as<JsonArrayConst>()){Vec tcp{};Joints q{};if(!arrayNumber(s["tcp"],tcp)||!integer(s["speedPercent"],1,100)||!integer(s["pauseMs"],0,600000)||!number(s["gripperDegrees"])||!inverse(core.profile,tcp,from,s["speedPercent"],q))return finish(false,"tcp-invalid");q[6]=s["gripperDegrees"];steps.push_back({q,s["speedPercent"],s["pauseMs"]});from=q;}}
  else return finish(false,"unsupported-command");const uint64_t startTime=clock?clock():mono;core.lastTick=startTime;bool ok=core.run(std::move(steps),startTime);if(ok)core.activeId=id;return finish(ok,ok?"started":"trajectory-invalid");
 }
};
}
