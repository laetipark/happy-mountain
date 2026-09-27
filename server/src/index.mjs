import { createAppServer } from './server.mjs';

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || '127.0.0.1';
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT는 1~65535 사이의 정수여야 합니다.');
}

const server = createAppServer();
server.listen(port, host, () => {
  console.log(`산등성이 웹 서버가 포트 ${port}에서 준비되었습니다.`);
});
server.on('error', () => {
  console.error('서버를 시작할 수 없습니다. 포트와 실행 권한을 확인해주세요.');
  process.exitCode = 1;
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => server.close());
}
