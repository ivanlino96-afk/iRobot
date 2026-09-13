import json, hashlib
from pathlib import Path
p=dict(version=1,homeRevision=1,kinematicsVersion='ik-dls-1',calibrated=True,geometryValidated=True,simulationOnly=True,sda=6,scl=7,heartbeatMs=1000,maxTickMs=100,linkRadius=0,minimum=[-80]*6+[0],maximum=[80]*6+[60],home=[0]*7,velocity=[15]*7,acceleration=[30]*7,tool=[0,0,140],boxes=[],axes=[{'origin':v,'axis':a} for v,a in zip([[0,0,80],[0,0,120],[0,0,70],[0,0,80],[0,0,80],[0,0,0]],[[0,0,1],[0,1,0],[0,1,0],[1,0,0],[0,1,0],[0,0,1]])],servos=[dict(joint=j,pcaChannel=i,zero=90,offset=0,ratio=(-1 if i==2 else 1),min=5,max=175,pulseMin=600,pulseMax=2400) for i,j in enumerate([0,1,1,2,3,4,5,6])])
Path('contracts/profile.simulation.json').write_text(json.dumps(p,indent=2)+'\n')
p['calibrated']=False;p['geometryValidated']=False;p['simulationOnly']=False
Path('contracts/profile.hardware-draft.json').write_text(json.dumps(p,indent=2)+'\n')
