// Package textnorm — 읽어 들인 SKILL.md·graph.json의 줄 끝을 LF로 맞춘다.
//
// Windows의 core.autocrlf=true 체크아웃은 파일을 CRLF로 풀어 놓는다. 판정·해시가
// 줄 끝 형식에 따라 달라지지 않도록, 파일은 모든 경로에서 ReadFile로 읽는다.
package textnorm

import (
	"bytes"
	"os"
)

// LF는 CRLF를 LF로 바꾼다. 단독 CR은 건드리지 않는다.
func LF(b []byte) []byte {
	return bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n"))
}

// ReadFile은 os.ReadFile 뒤 LF를 적용한다. 오류는 os.ReadFile의 것을 그대로 돌려준다.
func ReadFile(name string) ([]byte, error) {
	b, err := os.ReadFile(name)
	if err != nil {
		return nil, err
	}
	return LF(b), nil
}
