# coding=gb2312
import pyperclip

txt = input("enter:")
encoded = txt.encode("utf-16-le")

ret = ["{"]
for i, b in enumerate(encoded):
    if i > 0:
        ret.append(", ")
    ret.append("0x{:02X}".format(b))
ret.append("}, // ")
ret.append(txt)

print("".join(ret))
pyperclip.copy("".join(ret))
