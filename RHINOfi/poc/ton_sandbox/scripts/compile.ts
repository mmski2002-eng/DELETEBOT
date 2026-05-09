import { compileFunc, CompilerConfig } from '@ton-community/func-js';
import * as fs from 'fs';
import * as path from 'path';

async function compile() {
    const contractsDir = path.resolve(__dirname, '..', 'contracts');
    
    // Read the main contract 
    const contractPath = path.join(contractsDir, 'min_bridge.fc');
    const contractCode = fs.readFileSync(contractPath, 'utf8');

    console.log(`Compiling ${contractPath}...`);
    
    // The func-js compiler has stdlib built-in, we just need to pass the sources
    // as a map where key = path, value = content
    const sources: Record<string, string> = {};
    sources[contractPath] = contractCode;
    
    const config: CompilerConfig = {
        targets: [contractPath],
        sources: sources
    };

    const result = await compileFunc(config);
    
    if (result.status === 'ok') {
        console.log('✅ Compiled successfully');
        return result.codeBoc;
    } else {
        console.error('❌ Compilation failed:', result.message);
        throw new Error(result.message);
    }
}

export { compile };
