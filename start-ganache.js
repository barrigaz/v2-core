require("dotenv").config();
const { spawn } = require('child_process');
const subprocess = spawn('ganache-cli.cmd', 
	[
		'-f', 'https://mainnet.infura.io/v3/' + process.env.INFURA_API_KEY,
		'-e', 1000,
		'-m', process.env.MNEMONIC
	]);

subprocess.on('error', (err) => {
  console.error('Failed to start subprocess.');
});

subprocess.stdout.on('data', (data) => {
  console.log(`stdout: ${data}`);
});
