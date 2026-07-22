# app/ 디렉터리에서 `make app` 등을 쳐도 동작하도록 루트 Makefile 로 위임한다.
# 실제 타깃 정의는 ../Makefile 에 있다.
.PHONY: app web admin backend check reset setup

app web admin backend check reset setup:
	@$(MAKE) -C .. $@
