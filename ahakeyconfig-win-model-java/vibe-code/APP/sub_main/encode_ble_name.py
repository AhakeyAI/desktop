
# coding=gb2312
from urllib.parse import unquote
from urllib.parse import quote
import pyperclip
txt = input("enter:")
# txt = "あはは。"
out = quote(txt)
i=0
ret=['{']
while(True):
    t=out[i]
    if (t == '%'):
        ret.append('0x')
        ret.append(out[i+1:i+3])
        i+=2
    else:
        ret.append('\'')
        ret.append(t)
        ret.append('\'')
    i+=1
    if (i>=len(out)):
        break
    ret.append(', ')
ret.append('}, // ')
ret.append(txt)
print(''.join(ret))
pyperclip.copy(''.join(ret))
