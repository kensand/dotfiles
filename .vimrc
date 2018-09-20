call plug#begin('~/.vim/plugged')
"Plug 'maxboisvert/vim-simple-complete'"
if has('nvim')
  Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
else
  Plug 'Shougo/deoplete.nvim'
  Plug 'roxma/nvim-yarp'
  Plug 'roxma/vim-hug-neovim-rpc'
endif
let g:deoplete#enable_at_startup = 1
if !exists('g:deoplete#omni#input_patterns')
  let g:deoplete#omni#input_patterns = {}
endif
" let g:deoplete#disable_auto_complete = 1
autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | pclose | endif
" deoplete tab-complete
inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
Plug 'zchee/deoplete-jedi'

Plug 'Shougo/deoplete-clangx'
Plug 'carlitux/deoplete-ternjs', { 'do': 'npm install -g tern' }
  " For func argument completion
Plug 'Shougo/neosnippet'
Plug 'Shougo/neosnippet-snippets'
Plug 'Shougo/neoinclude.vim'

call plug#end()
colorscheme slate
set backspace=indent,eol,start

" deoplete

let g:deoplete#enable_at_startup = 1

" neosnippet
        
let g:neosnippet#enable_completed_snippet = 1

