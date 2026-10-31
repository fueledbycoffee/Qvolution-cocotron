#!/usr/bin/env python3
"""Original narrow RTF fixture oracle, independently authored from public format rules.

Not a general RTF implementation. No Cocotron parser/writer or Microsoft sample
reader code is imported/extracted. Validate only the generated readiness document.
"""
import argparse,copy,re
from pathlib import Path
EXPECTED='plain é e\u0301 \U0001d538 {brace}\\slash\nstyled tail'
def parse(data):
 text=data.decode('latin1');assert text.startswith('{\\rtf1'),'RTF version header'
 state=dict(dest='body',font=0,size=12.0,b=False,i=False,ul=False,color=None,align='left',uc=1,font_text='',rgb={})
 stack=[];chars=[];styles=[];fonts={};colors=[];skip=0;index=0
 def emit(c):
  nonlocal skip
  if skip:skip-=1;return
  if state['dest']=='font':
   if c==';':fonts[state['font']]=state['font_text'].strip();state['font_text']=''
   else:state['font_text']+=c
  elif state['dest']=='color':
   if c==';':colors.append(tuple(state['rgb'].get(k,0) for k in ('red','green','blue')) if state['rgb'] else None);state['rgb']={}
  elif state['dest']=='body':chars.append(c);styles.append(copy.deepcopy(state))
 while index<len(text):
  c=text[index];index+=1
  if c=='{':stack.append(copy.deepcopy(state));continue
  if c=='}':assert stack,'unbalanced close';state=stack.pop();continue
  if c in '\r\n':continue
  if c!='\\':emit(bytes([ord(c)]).decode('cp1252') if ord(c)>=128 else c);continue
  assert index<len(text),'trailing escape'
  c=text[index]
  if c in '{}\\':index+=1;emit(c);continue
  if c in '\r\n':index+=1;emit('\n');continue
  if c=='*':index+=1;state['dest']='ignore';continue
  if c=="'":assert index+3<=len(text);value=int(text[index+1:index+3],16);index+=3;emit(bytes([value]).decode('cp1252'));continue
  m=re.match(r'([a-zA-Z]+)(-?\d+)? ?',text[index:]);assert m,'unsupported control symbol'
  index+=len(m.group());word,arg=m.group(1),m.group(2);value=int(arg) if arg is not None else 1
  if word=='fonttbl':state['dest']='font'
  elif word=='colortbl':state['dest']='color'
  elif word in ('stylesheet','info','pict','generator'):state['dest']='ignore'
  elif word=='f':state['font']=value;state['font_text']=''
  elif word in ('red','green','blue'):assert 0<=value<=255;state['rgb'][word]=value
  elif word=='fs':state['size']=value/2
  elif word in ('b','i','ul'):state[word]=bool(value)
  elif word=='ulnone':state['ul']=False
  elif word=='cf':state['color']=value
  elif word=='uc':assert 0<=value<=16;state['uc']=value
  elif word=='u':
   assert -32768<=value<=32767,'Unicode escape outside signed16 format contract'
   emit(chr(value&0xffff));skip=state['uc']
  elif word in ('par','line'):emit('\n')
  elif word=='tab':emit('\t')
  elif word in ('qc','ql','qr','qj'):state['align']={'qc':'center','ql':'left','qr':'right','qj':'justify'}[word]
  elif word=='pard':state['align']='left'
  elif word=='plain':state.update(font=0,size=12.0,b=False,i=False,ul=False,color=None)
 assert not stack,'unbalanced document groups'
 raw=''.join(chars);decoded=raw.encode('utf-16-le','surrogatepass').decode('utf-16-le')
 return decoded,raw,styles,fonts,colors

def validate(data,paragraph=True):
 decoded,raw,styles,fonts,colors=parse(data);assert decoded==EXPECTED,('independent decoded text differs',repr(decoded))
 at=raw.index('styled');style=styles[at];name=fonts.get(style['font'],'')
 assert name in ('DejaVuSans','DejaVu Sans','DejaVuSans-BoldOblique','DejaVu Sans Bold Oblique'),('unrecognized actual fixture font',name)
 explicit_bolditalic=name.endswith('BoldOblique') or name.endswith('Bold Oblique')
 assert (style['b'] and style['i']) or explicit_bolditalic,'style lost bold/italic semantics'
 assert style['size']==19 and style['ul'],'styled size/underline lost'
 assert style['color'] is not None and colors[style['color']]==(255,0,0),'styled foreground is not red'
 tail=styles[raw.index('tail')];assert not tail['ul'] and not tail['b'] and not tail['i'] and tail['size']==17.5,'plain style did not reset'
 assert fonts.get(tail['font']) in ('DejaVuSans','DejaVu Sans'),'plain font did not reset'
 assert tail['color'] is None or colors[tail['color']] in (None,(0,0,0)),'plain tail incorrectly retains styled red'
 if paragraph:assert styles[0]['align']=='center','explicit centered paragraph not serialized'
 return len(decoded),len(styles)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('rtf',type=Path);p.add_argument('--without-paragraph',action='store_true');a=p.parse_args();print('PASS: independent RTF text/style oracle',validate(a.rtf.read_bytes(),not a.without_paragraph))
