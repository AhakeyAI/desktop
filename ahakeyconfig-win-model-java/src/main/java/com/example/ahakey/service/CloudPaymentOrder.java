package com.example.ahakey.service;

/** 支付订单（与 macOS 版一致） */
public class CloudPaymentOrder {
    public final CloudRechargePlan plan;
    public final int amountFen;
    public final String outTradeNo;
    public final String codeURL;
    public final String h5URL;
    public final String status;

    public CloudPaymentOrder(CloudRechargePlan plan, int amountFen, String outTradeNo, String codeURL, String h5URL, String status) {
        this.plan = plan;
        this.amountFen = amountFen;
        this.outTradeNo = outTradeNo;
        this.codeURL = codeURL;
        this.h5URL = h5URL;
        this.status = status;
    }

    public String paymentURL() {
        return codeURL.isEmpty() ? h5URL : codeURL;
    }

    public String amountText() {
        return String.format("%.2f 元", Math.max(0, amountFen) / 100.0);
    }
}