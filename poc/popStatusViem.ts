import { PopStatusManager,PopStatus } from "./popStatusManager";

async function main() {
  const ORACLE_ADDRESS =  (process.env.PRIVATE_KEY??"0x9b76A3d6A30c39E0020843D1a44E03A4AB42B6Bb") as `0x${string}`;
  const PRIVATE_KEY = (process.env.PRIVATE_KEY?? '0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133') as `0x${string}`;

  if (!ORACLE_ADDRESS || !PRIVATE_KEY) {
    throw new Error('Missing ORACLE_ADDRESS or PRIVATE_KEY environment variables');
  }

  const manager = new PopStatusManager(ORACLE_ADDRESS, PRIVATE_KEY);

  const name = 'mywebsite12';
  
  await manager.displayNameInfo(name);
  // We nee to mimick how pop work so calling the oracle here is ideal
  // Given that the registry will use it to check with the oracle for eligibility
  // Before using dotns users need to call this function to set their POP status 
  // This allows us to test various scenarios 
  await manager.setPopStatus(name, PopStatus.PopLite);
  
  await manager.displayNameInfo(name);
  
}

if (require.main === module) {
  main().catch(console.error);
}