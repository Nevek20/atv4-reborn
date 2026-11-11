// Decompila todas as funções entre dois endereços
// args: <arquivo_saida> <0xinicio> <0xfim>
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;

public class DecompRange extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        long ini = Long.parseLong(a[1].substring(2), 16), fim = Long.parseLong(a[2].substring(2), 16);
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        int n = 0;
        try (PrintWriter pw = new PrintWriter(new FileWriter(a[0]))) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(toAddr(ini), true)) {
                if (f.getEntryPoint().getOffset() >= fim) break;
                pw.println("// ===== " + f.getName() + " @ " + f.getEntryPoint() + "  tam " + f.getBody().getNumAddresses());
                DecompileResults r = di.decompileFunction(f, 120, monitor);
                pw.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// falhou");
                n++;
            }
        }
        println("funcoes: " + n);
    }
}
