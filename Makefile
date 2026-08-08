.PHONY: check defcompile test test-vim test-ui test-session test-mru test-highlight

check: defcompile test

defcompile:
	vim -Nu NONE -n -i NONE -es -S tests/defcompile.vim

test: test-vim test-ui test-session test-mru test-highlight

test-vim:
	vim -Nu NONE -n -i NONE -es -S tests/vim_smoke.vim

test-ui:
	vim -Nu NONE -n -i NONE -es -S tests/vim_ui.vim

test-session:
	vim -Nu NONE -n -i NONE -es -S tests/vim_session.vim

test-mru:
	vim -Nu NONE -n -i NONE -es -S tests/vim_mru.vim

test-highlight:
	vim -Nu NONE -n -i NONE -es -S tests/vim_highlight.vim
