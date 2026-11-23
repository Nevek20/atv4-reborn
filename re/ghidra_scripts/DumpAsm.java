// Lista o assembly das funções que contêm os endereços dados (VU0 legível,
// o descompilador embaralha as contas de vetor)
// args: <arquivo_saida> <0xEND> [0xEND ...]
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.*;
import java.io.*;

public class DumpAsm extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        try (PrintWriter pw = new PrintWriter(new FileWriter(a[0]))) {
            for (int i = 1; i < a.length; i++) {
                Address ad = toAddr(Long.parseLong(a[i].substring(2), 16));
                Function f = getFunctionContaining(ad);
                if (f == null) { disassemble(ad); createFunction(ad, null); f = getFunctionAt(ad); }
                if (f == null) { pw.println("// sem função em " + a[i]); continue; }
                pw.println("// ===== " + f.getName() + " @ " + f.getEntryPoint());
                InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    Instruction ins = it.next();
                    pw.println(ins.getAddress() + "  " + ins.toString());
                }
            }
        }
    }
}
