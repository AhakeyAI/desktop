package com.example.ahakey.service;
import com.example.ahakey.view.CloudAccountDialog;
import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.google.zxing.*;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import javafx.application.Platform;
import javafx.stage.*;
import javafx.scene.control.*;
import javafx.scene.image.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.concurrent.*;
import java.util.function.*;
public final class PackagedCloudProbe {
 static int checks;static CloudAccountDialog dialog;
 static void check(boolean b,String label){checks++;if(!b)throw new AssertionError(label);}
 static <T>T fx(Callable<T> c)throws Exception{var f=new FutureTask<T>(c);Platform.runLater(f);return f.get(10,TimeUnit.SECONDS);}
 static Stage window(String title){for(Window w:Window.getWindows())if(w instanceof Stage s&&s.isShowing()&&s.getTitle().equals(title))return s;return null;}
 static Button button(Stage w,String title){return w.getScene().getRoot().lookupAll(".button").stream().filter(n->n instanceof Button b&&b.getText().equals(title)).map(n->(Button)n).findFirst().orElseThrow();}
 static boolean text(Stage w,String part){return w!=null&&w.getScene().getRoot().lookupAll(".label").stream().anyMatch(n->n instanceof Label l&&l.getText().contains(part));}
 static void until(Callable<Boolean> condition)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);while(System.nanoTime()<end){if(fx(condition)){checks++;return;}Thread.sleep(10);}throw new AssertionError("UI condition timed out");}
 public static void main(String[] args)throws Exception{
  URI base=URI.create(args[0]);check(base.getHost().equals("127.0.0.1"),"loopback only");
  Path path=Path.of(System.getProperty("user.home"),"account.json");var cfg=new AhaTypeConfig(path,new WindowsCredentialStore());
  var aha=new AhaTypeService(cfg,HttpClient.newHttpClient(),base,Clock.systemUTC());var account=new CloudAccountManager(aha,Duration.ofMillis(20),Duration.ofSeconds(5));
  CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
  try{
   fx(()->{dialog=new CloudAccountDialog(null,account,()->{});dialog.show();Stage main=window("云端账号 · AhaType");for(var n:main.getScene().getRoot().lookupAll(".text-field"))if(n instanceof PasswordField f)f.setText("probe-password");else if(n instanceof TextField f)f.setText("probe-phone");button(main,"登录").fire();return null;});
   until(()->account.isLoggedIn()&&text(window("云端账号 · AhaType"),"当前账号：probe-phone"));
   check(Files.readString(path).contains("protected_state")&&!Files.readString(path).contains("probe-token"),"DPAPI envelope hides synthetic token");
   check(new AhaTypeConfig(path,new WindowsCredentialStore()).load().get("access_token").equals("probe-token"),"DPAPI decrypt reload roundtrip");
   fx(()->{button(window("云端账号 · AhaType"),"兑换码").fire();Stage w=window("兑换码");((TextField)w.getScene().getRoot().lookup(".text-field")).setText("probe-coupon");button(w,"确认兑换").fire();return null;});
   until(()->text(window("兑换码"),"兑换成功"));
   var order=account.createOrder(account.plans().get(0));
   fx(()->{var method=CloudAccountDialog.class.getDeclaredMethod("showPayment",CloudAccountManager.Order.class,long.class);method.setAccessible(true);method.invoke(dialog,order,0L);return null;});
   fx(()->{var image=window("微信扫码支付").getScene().getRoot().lookupAll("*").stream().filter(n->n instanceof ImageView).map(n->(ImageView)n).findFirst().orElseThrow();check(image!=null&&image.getImage()!=null,"actual payment window QR image");var img=image.getImage();int w=(int)img.getWidth(),h=(int)img.getHeight();int[] pixels=new int[w*h];img.getPixelReader().getPixels(0,0,w,h,PixelFormat.getIntArgbInstance(),pixels,0,w);String decoded=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new RGBLuminanceSource(w,h,pixels)))).getText();check(decoded.equals(order.url()),"rendered QR decodes to synthetic order URL");return null;});
   until(()->text(window("微信扫码支付"),"支付成功"));
   check(account.isLoggedIn(),"successful packaged HTTP flow retains session");
   System.out.println("PASS PackagedCloudProbe "+checks+" checks; packaged HttpClient/DPAPI/JavaFX/ZXing, external Python loopback only");
  }finally{fx(()->{if(dialog!=null)dialog.close();return null;});account.close();Platform.exit();}
 }
}
