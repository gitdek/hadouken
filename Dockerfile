FROM perl:5.20
COPY . /usr/src/hadouken


WORKDIR /usr/src/hadouken

RUN bash -c 'perl Makefile.PL --defaultdeps'
# CMD [ "perl", "Makefile.PL","--defaultdeps" ]

RUN make

RUN bash -c 'perl bin/hadouken'
#CMD [ "perl", "./bin/hadouken" ]

#CMD []
#ENTRYPOINT ["/usr/src/hadouken/bin/hadouken"]
