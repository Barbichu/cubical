all: 
	ghc --make -O2 -o cubical Main.hs
bnfc:
	bnfc -d Exp.cf
	happy -gca Exp/Par.y
	alex -g Exp/Lex.x
	ghc --make Exp/Test.hs -o Exp/Test
clean:
	rm -f *.log *.aux *.hi *.o cubigle
	cd Exp && rm -f ParExp.y LexExp.x LexhExp.hs \
                        ParExp.hs PrintExp.hs AbsExp.hs *.o *.hi
