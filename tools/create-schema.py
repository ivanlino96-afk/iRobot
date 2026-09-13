import json
from pathlib import Path
num={'type':'number'}
def arr(n,items=num):return {'type':'array','minItems':n,'maxItems':n,'items':items}
def obj(props):return {'type':'object','additionalProperties':False,'properties':props,'required':list(props)}
def integer(a,b):return {'type':'integer','minimum':a,'maximum':b}
servo=obj(dict(joint=integer(0,6),pcaChannel=integer(0,15),zero=num,offset=num,ratio=num,min={'type':'number','minimum':0,'maximum':180},max={'type':'number','minimum':0,'maximum':180},pulseMin={'type':'number','minimum':100,'maximum':3000},pulseMax={'type':'number','minimum':100,'maximum':3000}))
p=obj(dict(version=integer(1,2147483647),homeRevision=integer(1,2147483647),kinematicsVersion={'const':'ik-dls-1'},calibrated={'type':'boolean'},geometryValidated={'type':'boolean'},simulationOnly={'type':'boolean'},sda={'const':6},scl={'const':7},heartbeatMs=integer(100,10000),maxTickMs=integer(20,100),linkRadius={'type':'number','minimum':0},minimum=arr(7,{'type':'number','minimum':-360,'maximum':360}),maximum=arr(7,{'type':'number','minimum':-360,'maximum':360}),home=arr(7),velocity=arr(7,{'type':'number','exclusiveMinimum':0,'maximum':3600}),acceleration=arr(7,{'type':'number','exclusiveMinimum':0,'maximum':36000}),tool=arr(3),boxes={'type':'array','maxItems':8,'items':obj(dict(min=arr(3),max=arr(3)))},axes=arr(6,obj(dict(origin=arr(3),axis=arr(3)))),servos=arr(8,servo)))
p['$schema']='http://json-schema.org/draft-07/schema#'
Path('contracts/profile.schema.json').write_text(json.dumps(p,indent=2)+'\n')
