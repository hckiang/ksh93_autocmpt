curpos: curpos.c
	mkdir -p ksh93_autocmpt
	cc curpos.c -o ksh93_autocmpt/curpos

clean:
	rm -f *.o ksh93_autocmpt/curpos

install:
	cp -r ksh93_autocmpt "${HOME}"/.local/share
	cp autocmpt.sh "${HOME}"/.local/share/ksh93_autocmpt/
	#------------------------------------------------------------------------
	#
	#   Installed. Now please put the following line into your ~/.kshrc
	#
	#            . ~/.local/share/ksh93_autocmpt/autocmpt.sh
	#
	#------------------------------------------------------------------------
