
.PHONE: build-docker
build-docker:
	GOOS=linux GOARCH=amd64 go build -o vt-ingest
        docker build -t vt-ingest .


.PHONE: run
	docker run -it -v /Users/home/testdata/LEGAL:/testdata/legal --entrypoint=sh vt-ingest
