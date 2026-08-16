.PHONY: check defcompile test test-fixture test-vim test-ui test-sections test-remote test-session test-project test-mru test-highlight test-health test-window test-compat

check: defcompile test

defcompile:
	vim -Nu NONE -n -i NONE -es -S tests/defcompile.vim

test: test-fixture test-vim test-ui test-sections test-remote test-session test-project test-mru test-highlight test-health test-window test-compat

test-fixture:
	vim -Nu NONE -n -i NONE -es -S tests/vim_fixture.vim

test-vim:
	vim -Nu NONE -n -i NONE -es -S tests/vim_smoke.vim

test-ui:
	vim -Nu NONE -n -i NONE -es -S tests/vim_ui.vim

test-sections:
	vim -Nu NONE -n -i NONE -es -S tests/vim_sections.vim

test-remote:
	vim -Nu NONE -n -i NONE -es -S tests/vim_remote.vim

test-session:
	vim -Nu NONE -n -i NONE -es -S tests/vim_session.vim

test-project:
	vim -Nu NONE -n -i NONE -es -S tests/vim_project.vim

test-mru:
	vim -Nu NONE -n -i NONE -es -S tests/vim_mru.vim

test-highlight:
	vim -Nu NONE -n -i NONE -es -S tests/vim_highlight.vim

test-health:
	vim -Nu NONE -n -i NONE -es -S tests/vim_health.vim

test-window:
	vim -Nu NONE -n -i NONE -es -S tests/vim_window.vim

test-compat:
	vim -Nu NONE -n -i NONE -es -S tests/vim_compat.vim
