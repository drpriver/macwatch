INSTALLDIR=/usr/local/bin

macwatch: macwatch.m
	clang $< -o $@ -fobjc-arc
install: macwatch
	install -CS macwatch $(INSTALLDIR)
