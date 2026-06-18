import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 9999))
while True:
    data, _ = s.recvfrom(4096)
    print(data.decode("utf-8"))
