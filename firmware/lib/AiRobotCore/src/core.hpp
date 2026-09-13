#pragma once
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace airobot {
constexpr double pi=3.14159265358979323846;
using Joints=std::array<double,7>;
using Vec=std::array<double,3>;
using Mat=std::array<double,9>;
inline Vec add(Vec a,Vec b){return {a[0]+b[0],a[1]+b[1],a[2]+b[2]};}
inline Vec sub(Vec a,Vec b){return {a[0]-b[0],a[1]-b[1],a[2]-b[2]};}
inline Vec scale(Vec a,double s){return {a[0]*s,a[1]*s,a[2]*s};}
inline double dot(Vec a,Vec b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
inline Vec cross(Vec a,Vec b){return {a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};}
inline double norm(Vec v){return std::sqrt(dot(v,v));}
inline bool finite(double v){return std::isfinite(v);}
inline Mat identity(){return {1,0,0,0,1,0,0,0,1};}
inline Vec apply(Mat a,Vec b){return {a[0]*b[0]+a[1]*b[1]+a[2]*b[2],a[3]*b[0]+a[4]*b[1]+a[5]*b[2],a[6]*b[0]+a[7]*b[1]+a[8]*b[2]};}
inline Mat multiply(Mat a,Mat b){Mat c{};for(int i=0;i<3;i++)for(int j=0;j<3;j++)for(int k=0;k<3;k++)c[i*3+j]+=a[i*3+k]*b[k*3+j];return c;}
inline Mat rotation(Vec a,double degrees){double t=degrees*pi/180,c=cos(t),s=sin(t),d=1-c;return {c+a[0]*a[0]*d,a[0]*a[1]*d-a[2]*s,a[0]*a[2]*d+a[1]*s,a[1]*a[0]*d+a[2]*s,c+a[1]*a[1]*d,a[1]*a[2]*d-a[0]*s,a[2]*a[0]*d-a[1]*s,a[2]*a[1]*d+a[0]*s,c+a[2]*a[2]*d};}
struct Servo {int joint=-1,channel=-1;double zero=90,offset=0,ratio=1,min=0,max=0,pulseMin=0,pulseMax=0;};
struct Axis {Vec origin{},axis{0,0,1};};
struct Box {Vec min{},max{};};
struct Profile {
 std::string hash;int version=0,homeRevision=0;bool calibrated=false,geometryValidated=false,simulationOnly=true;
 Joints minimum{},maximum{},home{},velocity{},acceleration{};std::array<Servo,8> servos{};std::array<Axis,6> axes{};
 Vec tool{};std::vector<Box> boxes;double linkRadius=0;uint32_t heartbeatMs=0,maxTickMs=0;int sda=-1,scl=-1;
 bool valid()const{
  if(version<1||hash.size()!=64||heartbeatMs<100||heartbeatMs>10000||maxTickMs<20||maxTickMs>100||!finite(linkRadius)||linkRadius<0||boxes.size()>8)return false;
  std::array<int,7> count{};std::array<bool,16> used{};
  for(int j=0;j<7;j++)if(!finite(minimum[j])||!finite(maximum[j])||!finite(home[j])||!finite(velocity[j])||!finite(acceleration[j])||minimum[j]<-360||maximum[j]>360||minimum[j]>=maximum[j]||home[j]<minimum[j]||home[j]>maximum[j]||velocity[j]<=0||velocity[j]>3600||acceleration[j]<=0||acceleration[j]>36000)return false;
  for(auto s:servos){if(s.joint<0||s.joint>6||s.channel<0||s.channel>15||used[s.channel]||!finite(s.ratio)||fabs(s.ratio)<1e-9||!finite(s.zero)||!finite(s.offset)||!finite(s.min)||!finite(s.max)||s.min>=s.max||s.min<0||s.max>180||!finite(s.pulseMin)||!finite(s.pulseMax)||s.pulseMin<100||s.pulseMax>3000||s.pulseMin>=s.pulseMax)return false;used[s.channel]=true;count[s.joint]++;}
  for(int j=0;j<7;j++)if(count[j]!=(j==1?2:1))return false;
  for(auto a:axes){for(double v:a.origin)if(!finite(v))return false;if(!finite(norm(a.axis))||fabs(norm(a.axis)-1)>1e-6)return false;}
  for(double v:tool)if(!finite(v))return false;
  for(auto b:boxes)for(int i=0;i<3;i++)if(!finite(b.min[i])||!finite(b.max[i])||b.min[i]>=b.max[i])return false;
  return legal(home);
 }
 bool legal(const Joints&q)const{for(int j=0;j<7;j++)if(!finite(q[j])||q[j]<minimum[j]-1e-8||q[j]>maximum[j]+1e-8)return false;for(auto s:servos){if(s.joint<0||s.joint>6)return false;double v=s.zero+s.offset+s.ratio*q[s.joint];if(!finite(v)||v<s.min-1e-8||v>s.max+1e-8)return false;}return true;}
 std::array<double,8> pulses(const Joints&q)const{std::array<double,8> r{};for(int i=0;i<8;i++){auto s=servos[i];double d=s.zero+s.offset+s.ratio*q[s.joint];r[i]=s.pulseMin+d/180*(s.pulseMax-s.pulseMin);}return r;}
};
struct Pose {Vec position{};Mat orientation=identity();std::array<Vec,8> points{};};
inline Pose forward(const Profile&p,const Joints&q){Pose f;for(int i=0;i<6;i++){f.position=add(f.position,apply(f.orientation,p.axes[i].origin));f.points[i+1]=f.position;f.orientation=multiply(f.orientation,rotation(p.axes[i].axis,q[i]));}f.position=add(f.position,apply(f.orientation,p.tool));f.points[7]=f.position;return f;}
inline bool segmentBox(Vec a,Vec b,Box box,double pad){double lo=0,hi=1;for(int i=0;i<3;i++){double d=b[i]-a[i],mn=box.min[i]-pad,mx=box.max[i]+pad;if(fabs(d)<1e-12){if(a[i]<mn||a[i]>mx)return false;}else{double x=(mn-a[i])/d,y=(mx-a[i])/d;if(x>y)std::swap(x,y);lo=std::max(lo,x);hi=std::min(hi,y);if(lo>hi)return false;}}return true;}
inline bool collision(const Profile&p,const Joints&q,double pad=0){auto f=forward(p,q);for(auto b:p.boxes)for(int i=0;i<7;i++)if(segmentBox(f.points[i],f.points[i+1],b,p.linkRadius+pad))return true;return false;}
inline double duration(const Profile&p,const Joints&a,const Joints&b,int speed){if(speed<1||speed>100)return INFINITY;double t=.02;for(int j=0;j<7;j++){double d=fabs(b[j]-a[j]);t=std::max(t,std::max(1.875*d/(p.velocity[j]*speed/100.),sqrt(5.774*d/p.acceleration[j])));}return ceil(t/.02)*.02;}
inline double blend(double u){return u*u*u*(10+u*(-15+6*u));}
inline Joints interpolate(Joints a,Joints b,double u){Joints q{};double s=blend(u);for(int j=0;j<7;j++)q[j]=a[j]+(b[j]-a[j])*s;return q;}
// Conservative swept-link enclosure: inflate each sampled link by a bound on
// endpoint travel to the next sample. Includes all intermediate link positions.
inline bool pathLegal(const Profile&p,Joints a,Joints b){if(!p.legal(a)||!p.legal(b))return false;double delta=0,r=norm(p.tool);for(auto axis:p.axes)r+=norm(axis.origin);for(int j=0;j<6;j++)delta+=fabs(b[j]-a[j])*pi/180;int n=std::max(1,int(ceil(delta*180/pi)));if(n>2160)return false;double pad=r*delta/n;for(int i=0;i<=n;i++){Joints q{};for(int j=0;j<7;j++)q[j]=a[j]+(b[j]-a[j])*i/n;if(collision(p,q,pad))return false;}return true;}
inline bool trajectoryLegal(const Profile&p,Joints a,Joints b,int speed){if(!pathLegal(p,a,b)||speed<1||speed>100)return false;double t=duration(p,a,b,speed);int n=std::max(100,int(ceil(t/.02)));if(n>30000)return false;for(int i=0;i<=n;i++){double u=double(i)/n;auto q=interpolate(a,b,u),halt=q;Joints vel{};double brake=.02;for(int j=0;j<7;j++){vel[j]=(b[j]-a[j])*30*u*u*(1-u)*(1-u)/t;brake=std::max(brake,fabs(vel[j])/p.acceleration[j]);}for(int j=0;j<7;j++)halt[j]+=vel[j]*brake/2;if(!pathLegal(p,q,halt))return false;}return true;}
inline std::array<double,6> poseError(Pose current,Pose target){Vec d=sub(target.position,current.position),r{};for(int i=0;i<3;i++)r=add(r,cross({current.orientation[i],current.orientation[i+3],current.orientation[i+6]},{target.orientation[i],target.orientation[i+3],target.orientation[i+6]}));return {d[0],d[1],d[2],r[0]*50,r[1]*50,r[2]*50};}
inline double orientationDistance(Mat a,Mat b){double trace=0;for(int i=0;i<9;i++)trace+=a[i]*b[i];return acos(std::max(-1.,std::min(1.,(trace-1)/2)));}
inline bool solve6(double a[6][7],double x[6]){for(int i=0;i<6;i++){int row=i;for(int k=i+1;k<6;k++)if(fabs(a[k][i])>fabs(a[row][i]))row=k;if(fabs(a[row][i])<1e-12)return false;for(int j=i;j<7;j++)std::swap(a[i][j],a[row][j]);double div=a[i][i];for(int j=i;j<7;j++)a[i][j]/=div;for(int k=0;k<6;k++)if(k!=i){double v=a[k][i];for(int j=i;j<7;j++)a[k][j]-=v*a[i][j];}}for(int i=0;i<6;i++)x[i]=a[i][6];return true;}
inline bool inverse(const Profile&p,Vec tcp,const Joints&from,int speed,Joints&best){if(!p.geometryValidated||!p.calibrated||!p.legal(from))return false;for(double x:tcp)if(!finite(x))return false;Pose target=forward(p,p.home);target.position=add(target.position,tcp);double bestTime=INFINITY,bestTravel=INFINITY;bool found=false;
 for(int seed=0;seed<9;seed++){Joints q=seed==0?from:p.home;if(seed>1)for(int j=0;j<6;j++)q[j]=p.minimum[j]+(p.maximum[j]-p.minimum[j])*((seed+j*3)%7+1)/8.;q[6]=from[6];
  for(int it=0;it<100;it++){auto f=forward(p,q);auto e=poseError(f,target);if(norm(sub(f.position,target.position))<=.05&&orientationDistance(f.orientation,target.orientation)<=.001)break;double jac[6][6]{};for(int j=0;j<6;j++){auto v=q;v[j]+=.001;auto ee=poseError(forward(p,v),target);for(int k=0;k<6;k++)jac[k][j]=(e[k]-ee[k])/.001;}double a[6][7]{};for(int i=0;i<6;i++){for(int j=0;j<6;j++){for(int k=0;k<6;k++)a[i][j]+=jac[k][i]*jac[k][j];if(i==j)a[i][j]+=.01;}for(int k=0;k<6;k++)a[i][6]+=jac[k][i]*e[k];}double x[6]{};if(!solve6(a,x))break;for(int j=0;j<6;j++)q[j]=std::max(p.minimum[j],std::min(p.maximum[j],q[j]+std::max(-5.,std::min(5.,x[j]))));}
  auto f=forward(p,q);if(norm(sub(f.position,target.position))>.05||orientationDistance(f.orientation,target.orientation)>.001||!trajectoryLegal(p,from,q,speed))continue;double t=duration(p,from,q,speed),travel=0;for(int j=0;j<6;j++)travel+=fabs(q[j]-from[j])/(p.maximum[j]-p.minimum[j]);if(t<bestTime-1e-9||(fabs(t-bestTime)<=1e-9&&(travel<bestTravel-1e-9||(fabs(travel-bestTravel)<=1e-9&&q<best)))){best=q;bestTime=t;bestTravel=travel;found=true;}}
 return found;
}
enum class State {BOOT_LOCKED,UNCALIBRATED,CALIBRATING,READY,EXECUTING,STOPPING,HOLD,FAULT,ESTOP_LATCHED};
inline const char* name(State s){static const char*n[]={"BOOT_LOCKED","UNCALIBRATED","CALIBRATING","READY","EXECUTING","STOPPING","HOLD","FAULT","ESTOP_LATCHED"};return n[int(s)];}
struct Step {Joints target{};int speed=10;uint32_t pauseMs=0;};
struct Core {
 Profile profile;State state=State::BOOT_LOCKED;Joints q{},v{},start{},end{},stopV{};bool referenced=false,outputKnown=true;std::string reason="boot",activeId;uint64_t heartbeat=0,lastTick=0,started=0,pauseUntil=0;double seconds=0;std::vector<Step> program;size_t step=0;bool moving=false;
 bool configure(const Profile&p){if(state==State::EXECUTING||state==State::STOPPING||state==State::CALIBRATING||!p.valid())return false;profile=p;referenced=false;if(state!=State::ESTOP_LATCHED&&state!=State::FAULT)state=p.calibrated?State::BOOT_LOCKED:State::UNCALIBRATED;return true;}
 bool reference(Joints actual){if(state!=State::BOOT_LOCKED||!profile.calibrated||!profile.valid()||!profile.legal(actual)||collision(profile,actual))return false;q=actual;v={};referenced=true;return true;}
 bool enable(uint64_t now){if(state!=State::BOOT_LOCKED||!referenced||!profile.calibrated)return false;state=State::READY;heartbeat=lastTick=now;reason="enabled";return true;}
 void beat(uint64_t now){heartbeat=now;}
 void latch(){program.clear();moving=false;state=State::ESTOP_LATCHED;v={};reason="software-latch";referenced=false;}
 void fault(const std::string&r){program.clear();moving=false;v={};referenced=false;outputKnown=false;if(state!=State::ESTOP_LATCHED)state=State::FAULT;reason=r;}
 bool reset(){if(state!=State::ESTOP_LATCHED&&state!=State::FAULT)return false;state=State::BOOT_LOCKED;referenced=false;reason="reset-awaiting-reference";return true;}
 bool acknowledge(){if(state!=State::HOLD||!referenced)return false;state=State::READY;reason="acknowledged";return true;}
 bool run(std::vector<Step> steps,uint64_t now){if(state!=State::READY||steps.empty()||steps.size()>32)return false;auto prev=q;for(auto s:steps){if(s.speed<1||s.speed>100||s.pauseMs>600000||!trajectoryLegal(profile,prev,s.target,s.speed))return false;prev=s.target;}program=std::move(steps);step=0;state=State::EXECUTING;beginStep(now);return true;}
 void beginStep(uint64_t now){start=q;end=program[step].target;seconds=duration(profile,start,end,program[step].speed);started=now;pauseUntil=0;moving=true;}
 void stop(uint64_t now,const std::string&r){if(state==State::ESTOP_LATCHED||state==State::FAULT||state==State::BOOT_LOCKED||state==State::UNCALIBRATED)return;program.clear();reason=r;start=q;stopV=v;seconds=.02;for(int j=0;j<7;j++)seconds=std::max(seconds,fabs(v[j])/profile.acceleration[j]);end=q;for(int j=0;j<7;j++)end[j]+=v[j]*seconds/2;if(!pathLegal(profile,q,end)){fault("stop-path-invalid");return;}started=now;state=State::STOPPING;moving=true;}
 bool tick(uint64_t now,bool control){if(state!=State::EXECUTING&&state!=State::STOPPING&&state!=State::READY&&state!=State::CALIBRATING)return false;if((state==State::EXECUTING||state==State::STOPPING)&&lastTick&&now-lastTick>profile.maxTickMs){fault("control-deadline");return false;}lastTick=now;
  if(state!=State::STOPPING&&(!control||now-heartbeat>profile.heartbeatMs))stop(now,"control-lost");
  if(state==State::STOPPING){double t=std::min(seconds,(now-started)/1000.);auto next=start;for(int j=0;j<7;j++){next[j]+=stopV[j]*(t-t*t/(2*seconds));v[j]=stopV[j]*(1-t/seconds);}if(!profile.legal(next)){fault("stop-limit");return false;}q=next;if(t>=seconds){state=State::HOLD;v={};moving=false;}return true;}
  if(state!=State::EXECUTING)return false;
  if(!moving){if(now<pauseUntil)return false;if(++step>=program.size()){program.clear();state=State::READY;reason="completed";return false;}beginStep(now);}
  double u=std::min(1.,(now-started)/(seconds*1000));Joints next=interpolate(start,end,u);for(int j=0;j<7;j++)v[j]=(end[j]-start[j])*30*u*u*(1-u)*(1-u)/seconds;
  // Every point must admit its bounded-acceleration stopping extension.
  double brake=.02;for(int j=0;j<7;j++)brake=std::max(brake,fabs(v[j])/profile.acceleration[j]);auto halt=next;for(int j=0;j<7;j++)halt[j]+=v[j]*brake/2;
  if(!pathLegal(profile,next,halt)){fault("stopping-envelope");return false;}q=next;if(u>=1){v={};moving=false;pauseUntil=now+program[step].pauseMs;}return true;
 }
};
// Session replay guard. Verification of signature and envelope happens before this.
struct Replay {
 std::string session;uint64_t last=0;struct Entry{std::string id,digest,result;uint64_t seq;};std::vector<Entry> cache;
 void open(std::string s){session=std::move(s);last=0;cache.clear();}
 std::string accept(std::string id,uint64_t seq,std::string digest){for(auto&e:cache)if(e.id==id){if(e.seq==seq&&e.digest==digest)return "duplicate:"+e.result;return "id-reused";}if(seq==0||seq<=last||seq>9007199254740991ULL)return "sequence";last=seq;if(cache.size()==64)cache.erase(cache.begin());cache.push_back({id,digest,"accepted",seq});return "ok";}
 void result(const std::string&id,const std::string&r){for(auto&e:cache)if(e.id==id)e.result=r;}
};
}
