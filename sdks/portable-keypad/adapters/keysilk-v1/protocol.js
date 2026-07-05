export const keysilkV1Protocol = {
  vendorId: 0x4132,
  productId: 0x2107,
  reportLength: 64,
  payloadLength: 60,
  commands: {
    handshake: 0x0a,
    readBlock: 0x0d,
    writeBlock: 0x0b,
    switchLayer: 0x0c,
    finishWrite: 0x0f,
    finishRead: 0x1f,
  },
};

export function makeReadBlockReport(offset) {
  const report = new Uint8Array(keysilkV1Protocol.reportLength);
  report[0] = keysilkV1Protocol.commands.readBlock;
  report[2] = (offset >> 8) & 0xff;
  report[3] = offset & 0xff;
  fillProbeTail(report);
  return report;
}

export function makeWriteBlockReport(offset, payload) {
  if (payload.length > keysilkV1Protocol.payloadLength) {
    throw new Error("KeySilk write payload must be 60 bytes or less");
  }
  const report = new Uint8Array(keysilkV1Protocol.reportLength);
  report[0] = keysilkV1Protocol.commands.writeBlock;
  report[2] = (offset >> 8) & 0xff;
  report[3] = offset & 0xff;
  report.set(payload, 4);
  return report;
}

export function splitConfigIntoWriteReports(configBytes) {
  const reports = [];
  for (let offset = 0; offset < configBytes.length; offset += keysilkV1Protocol.payloadLength) {
    reports.push(makeWriteBlockReport(offset, configBytes.slice(offset, offset + keysilkV1Protocol.payloadLength)));
  }
  return reports;
}

function fillProbeTail(report) {
  for (let i = 5; i < report.length; i += 1) {
    report[i] = i;
  }
}
