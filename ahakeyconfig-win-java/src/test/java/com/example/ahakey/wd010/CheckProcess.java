package com.example.ahakey.wd010;

/** Allows old standalone checks with leaked AWT threads to return their real exit status. */
public final class CheckProcess {
    public static void main(String[] args){
        int exit=0;
        try{Class.forName(args[0]).getMethod("main",String[].class).invoke(null,(Object)java.util.Arrays.copyOfRange(args,1,args.length));}
        catch(Throwable failure){while(failure instanceof java.lang.reflect.InvocationTargetException&&failure.getCause()!=null)failure=failure.getCause();failure.printStackTrace();exit=1;}
        System.exit(exit);
    }
}
