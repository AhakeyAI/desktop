package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.JsonParser;
import java.io.*;
import java.math.BigInteger;
import java.nio.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.util.*;

/** AhaKey release signature v1. Trust comes only from the installed public key. */
public final class ReleaseSignature {
    public static final long MAX_FILE = 2L * 1024 * 1024 * 1024;
    private static final byte[] MAGIC="AHAKSIG1".getBytes(StandardCharsets.US_ASCII), FOOTER="AHAKEND1".getBytes(StandardCharsets.US_ASCII);
    private final PublicKey key;
    public record Identity(long prefixLength,String prefixHash,String version,String variant,String arch,String productId,String upgradeCode,String productCode) {}
    public ReleaseSignature(PublicKey key) {
        if(!(key instanceof RSAPublicKey rsa)||rsa.getModulus().bitLength()!=3072||!rsa.getPublicExponent().equals(BigInteger.valueOf(65537)))throw new IllegalArgumentException("发行公钥必须为RSA3072/e65537");
        this.key=key;
    }
    public static PublicKey publicKey(String modulus,String exponent)throws GeneralSecurityException {
        return KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(new BigInteger(1,Base64.getDecoder().decode(modulus)),new BigInteger(1,Base64.getDecoder().decode(exponent))));
    }
    public static ReleaseSignature production()throws IOException {
        try(var in=ReleaseSignature.class.getResourceAsStream("/update/release-public-key.json")) {
            if(in==null)throw new IOException("发行公钥资源缺失");
            var j=new ObjectMapper().enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION).readTree(in);
            if(j.path("schema").asInt()!=1)throw new IOException("发行公钥格式无效");
            return new ReleaseSignature(publicKey(j.path("modulus").asText(),j.path("exponent").asText()));
        }catch(GeneralSecurityException|IllegalArgumentException e){throw new IOException("发行公钥无效",e);}
    }
    /** Read-only package verification used by the isolated release recipe. */
    public static void main(String[] args)throws Exception {
        if(args.length!=1)throw new IllegalArgumentException("Expected one installer path");
        System.out.println(new ObjectMapper().writeValueAsString(production().verify(Path.of(args[0]))));
    }
    public Identity verify(Path file)throws IOException {
        try(var in=new RandomAccessFile(file.toFile(),"r")) {
            long total=in.length();if(total<464||total>MAX_FILE)throw new IOException("发行包大小无效");
            byte[] footer=new byte[16];in.seek(total-16);in.readFully(footer);
            var f=ByteBuffer.wrap(footer).order(ByteOrder.LITTLE_ENDIAN);byte[] marker=new byte[8];f.get(marker);
            long length=Integer.toUnsignedLong(f.getInt());
            if(!Arrays.equals(marker,FOOTER)||f.getInt()!=1||length<64||length>2048||length>total-400)throw new IOException("发行签名尾部无效");
            long prefixLength=total-400-length;byte[] payload=new byte[(int)length],signature=new byte[384];
            in.seek(prefixLength);in.readFully(payload);in.readFully(signature);
            Signature verifier=Signature.getInstance("SHA256withRSA");verifier.initVerify(key);verifier.update(payload);
            if(!verifier.verify(signature))throw new IOException("发行签名不可信");
            Identity identity=parsePayload(payload);
            if(identity.prefixLength()!=prefixLength||prefixLength<2)throw new IOException("发行包prefix长度不匹配");
            if(prefixLength>=16){in.seek(prefixLength-16);in.readFully(marker);if(Arrays.equals(marker,FOOTER))throw new IOException("发行包重复签名");}
            in.seek(0);if(in.readUnsignedByte()!=0x4d||in.readUnsignedByte()!=0x5a)throw new IOException("发行包不是EXE");in.seek(0);
            MessageDigest digest=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];long remaining=prefixLength;
            while(remaining>0){int count=in.read(buffer,0,(int)Math.min(buffer.length,remaining));if(count<0)throw new EOFException();digest.update(buffer,0,count);remaining-=count;}
            if(!HexFormat.of().formatHex(digest.digest()).equals(identity.prefixHash()))throw new IOException("发行包内容已改变");
            return identity;
        }catch(GeneralSecurityException|IllegalArgumentException|BufferUnderflowException e){throw new IOException("发行签名格式或身份无效",e);}
    }
    public static Identity parsePayload(byte[] payload)throws IOException {
        try{
            var b=ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN);byte[] magic=new byte[8],hash=new byte[32];b.get(magic);long prefix=b.getLong();b.get(hash);
            if(!Arrays.equals(magic,MAGIC)||prefix<2||prefix>MAX_FILE)throw new IOException("发行payload无效");
            String[] values=new String[6];for(int i=0;i<values.length;i++){
                int length=Short.toUnsignedInt(b.getShort());if(length<1||length>128||length>b.remaining())throw new IOException("发行字段长度无效");
                byte[] bytes=new byte[length];b.get(bytes);values[i]=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
                if(values[i].codePoints().anyMatch(c->Character.isISOControl(c)))throw new IOException("发行字段含控制字符");
            }
            if(b.hasRemaining())throw new IOException("发行payload含多余字段");
            InstalledAppIdentity.compareVersions(values[0],values[0]);
            if(!Set.of("lite","local-model").contains(values[1])||!values[2].equals("x64")||!values[3].equals(InstalledAppIdentity.PRODUCT)
                    ||!values[4].equalsIgnoreCase(InstalledAppIdentity.UPGRADE_CODE)||!guid(values[5]))throw new IOException("发行安装身份无效");
            return new Identity(prefix,HexFormat.of().formatHex(hash),values[0],values[1],values[2],values[3],values[4],values[5]);
        }catch(BufferUnderflowException e){throw new IOException("发行payload截断",e);}
    }
    private static boolean guid(String value){return value.matches("\\{[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}}");}
}
