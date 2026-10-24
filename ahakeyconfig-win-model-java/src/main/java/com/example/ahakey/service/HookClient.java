package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.net.Socket;
import java.net.InetSocketAddress;

public class HookClient {
    private static final String DEFAULT_HOST = "localhost";
    private static final int DEFAULT_PORT = 8765;
    private static final ObjectMapper mapper = new ObjectMapper();

    public static int run(String event) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(DEFAULT_HOST, DEFAULT_PORT));

            OutputStream out = socket.getOutputStream();
            InputStream in = socket.getInputStream();

            String request = String.format("{\"cmd\":\"%s\"}", event);
            out.write(request.getBytes());
            out.flush();

            BufferedReader reader = new BufferedReader(new InputStreamReader(in));
            String response = reader.readLine();

            if (response != null) {
                JsonNode node = mapper.readTree(response);
                System.out.println(response);
            }

            return 0;
        } catch (IOException e) {
            System.err.println("Hook 客户端连接失败: " + e.getMessage());
            return 1;
        }
    }

    public static int sendCommand(String cmd, int value) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(DEFAULT_HOST, DEFAULT_PORT));

            OutputStream out = socket.getOutputStream();
            InputStream in = socket.getInputStream();

            String request = String.format("{\"cmd\":\"%s\",\"value\":%d}", cmd, value);
            out.write(request.getBytes());
            out.flush();

            BufferedReader reader = new BufferedReader(new InputStreamReader(in));
            String response = reader.readLine();

            if (response != null) {
                System.out.println(response);
            }

            return 0;
        } catch (IOException e) {
            System.err.println("发送命令失败: " + e.getMessage());
            return 1;
        }
    }

    public static String queryStatus() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(DEFAULT_HOST, DEFAULT_PORT));

            OutputStream out = socket.getOutputStream();
            InputStream in = socket.getInputStream();

            String request = "{\"cmd\":\"status\"}";
            out.write(request.getBytes());
            out.flush();

            BufferedReader reader = new BufferedReader(new InputStreamReader(in));
            return reader.readLine();

        } catch (IOException e) {
            return "{\"error\":\"" + e.getMessage() + "\"}";
        }
    }
}