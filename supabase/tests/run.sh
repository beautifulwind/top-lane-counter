#!/bin/sh
# DB 권한·승인 함수 검사: 로컬 Docker Postgres에 깨끗한 DB를 만들고
# Supabase 흉내(supabase_stub.sql) → schema.sql → migrations/* → *_test.sql 순서로 실행한다.
# 사용법: sh supabase/tests/run.sh   (실제 Supabase에는 아무것도 하지 않음)
set -e
cd "$(dirname "$0")/.."
NAME=tlc-pg
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker start "$NAME" >/dev/null 2>&1 || docker run -d --name "$NAME" -e POSTGRES_PASSWORD=pg postgres:16-alpine >/dev/null
  until docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
fi
docker exec "$NAME" psql -U postgres -q -c "drop database if exists tlc" -c "create database tlc" 2>/dev/null
for f in tests/supabase_stub.sql schema.sql migrations/*.sql tests/*_test.sql; do
  echo "== $f"
  # 결과 행은 버리고, PASS/FAIL 알림과 오류만 보여 준다. 오류가 나면 거기서 멈춘다.
  if ! out=$(docker exec -i "$NAME" psql -U postgres -d tlc -v ON_ERROR_STOP=1 -q < "$f" 2>&1 >/dev/null); then
    printf '%s\n' "$out" | sed -e 's/^psql:<stdin>:[0-9]*: //' -e 's/^NOTICE:  //'
    echo "실패: $f"; exit 1
  fi
  printf '%s\n' "$out" | sed -e 's/^psql:<stdin>:[0-9]*: //' -e 's/^NOTICE:  //' | grep -v '^$' || true
done
echo "모두 통과"
