// Version 01-18-2017 by IA
//
// This code is used to batch upload media to Veritone.  Things to check:
// *  Provide the correct API key for this account
// *  The channel size must support the total number of files to be processed
// *  Select the correct engine tasks for this client (Voicebase is most common)
//

package main

import (
	"bufio"
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"github.com/jawher/mow.cli"
	"math"
	"github.com/elgs/gojq"
	"github.com/xlab/closer"
	"github.com/docker/docker/pkg/discovery/file"
)


var (
	app = cli.App("mysendv2", "Create job")

	cfgToken= app.StringOpt("token", os.Getenv("TOKEN"), "contain terms for Voicebase")
	terms_file = app.StringOpt("terms_file", os.Getenv("TERMS_FILE"), "contain terms for Voicebase")
	inputDir = app.StringOpt("in", os.Getenv("INDIR"), "Input directory containing the media files")
	outputDir = app.StringOpt("out", os.Getenv("OUTDIR"), "output directory for the results")
	webhookUrl = app.StringOpt("webhook", os.Getenv("WEBHOOK_URL"), "webhook url to receive done job")

	// TODO engines and their payloads
/* Kirby - CME */
//cfgAppID = "c8589dac-244a-4fd5-bd5f-68808d8df4b5"
//cfgToken = "79962d:8e3aff1ecb5d4a5ab1980900ad92386b6f75bced89ab45e69e397ace1976ea97"
//var cfgTerms = "Silver, SIFO, Gottlieb, Clerk, Floor, Expire, Settlement, LBMA, London Bullion, Committee, Trade, Exchange, Forward, Hedge, Roll, Spread, Switch, Butterfly, Backwardated, Contango, Indicative, backspread, decay, straddle, troy ounce, position limit, compliance, Bear Stearns, Margin, z1, z2, z3, z4, u1, u2, u3, u4, n2, n3, n4, h2, h3, h4, Longdated, VWAP, Upstairs, Cancel, Kill, FOK, Fill, kill, IOC, Immediate, cancel, AON, All or None, GTC, Good-Til-Cancelled, Squeeze, Pressure, Locals, Liquidity, Lower, Higher, Rho, High end, High side, Low end, Low side, Run over, Ran over, Came in, Came out, Collapse, Widen, Tighten, Wider, Tigher, CPTN, Captain, PLS, Sylvestri, Fairview, GID, Diorgano, AC, Cicileo, Hugo, Hansen, Socks, Sox, Doug, McSorley, Hillebrenner, Cazakoff, Grumet, Kline, Greenberg, Weldon, OLS, Ollie, Sabin, Sabin Metals, BG, Bobby, Gott, Bob, Mung, Munging, Munged, Munger, Park, Mizrahi, Scott, Middletown, Arch, Danny, Shak, Shaq, SHK, KMG, McGrane, Rossi, Frack, Wack, Wacker, Grundy, Blythe, Masters"
//cfgTerms = ""
     // CMS
     cfgAppID = "8a37c1d0-3f3b-48d0-a84e-2b8e3646fbe5"
)
func appendError(s string) {
	fmt.Println(s)
}

func appendLog(s string) {
	fmt.Println(s)
}

func getTerms() string {
	if (len(*terms_file)>0) {
		return ioutil.ReadFile(*terms_file)
	}
    return ""
}

func hashFileMd5(filePath string) (string, error) {
	var returnMD5String string
	file, err := os.Open(filePath)
	if err != nil {
		return returnMD5String, err
	}
	defer file.Close()
	hash := md5.New()
	if _, err := io.Copy(hash, file); err != nil {
		return returnMD5String, err
	}
	hashInBytes := hash.Sum(nil)[:16]
	returnMD5String = hex.EncodeToString(hashInBytes)
	return returnMD5String, nil

}

func submitFile(filename string) string {

	extension := filepath.Ext(filename)[1:]
	//basename := filename[:len(filename)-len(extName)]
	timenow := time.Now().Unix()
	timestart := strconv.FormatInt(timenow, 10)
	timeend := strconv.FormatInt(timenow+getDuration(filename), 10)

	bodyObj := `{"applicationId":"` + cfgAppID + `","startDateTime": ` + timestart + `, "stopDateTime": ` + timeend + `, "metadata":{"veritone-file":{"filename":"` + filename + `"}}}`
	//fmt.Printf("body=%s", bodyObj)

	// Create recording
	req, err := http.NewRequest("POST", "https://api.veritone.com/v1/recording", bytes.NewReader([]byte(bodyObj)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+*cfgToken)
	resp, err := http.DefaultClient.Do(req)
	jsonObj, err := ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	fmt.Printf("json=%s", jsonObj)

	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	parser, err := gojq.NewStringQuery(string(jsonObj))

	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	recordingIDx, err := parser.Query("recordingId")
	recordingID := recordingIDx.(string)

	md5Hash, err := hashFileMd5("in/" + filename)
	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	//Note that you can Post with an io.Reader as the body:
	file, err := os.Open("in/" + filename)
	defer file.Close()

	// Add file as an asset
	req, err = http.NewRequest("POST", "https://api.veritone.com/v1/recording/"+recordingID+"/asset", file)
	req.Header.Set("Content-Type", "audio/"+extension)
	req.Header.Set("Authorization", "Bearer "+cfgToken)
	req.Header.Set("X-Veritone-MD5-Checksum", md5Hash)
	req.Header.Set("X-Veritone-Asset-Type", "media")
	resp, err = http.DefaultClient.Do(req)
	jsonObj, err = ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	fmt.Printf("json=%s", jsonObj)

	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	termsPayload := ""
	// read terms paylahod
	if len(cfgTerms) > 0 {
		termsPayload = `",terms": "` + cfgTerms + `"`
	}

	bodyObj = `{"applicationId":"` + cfgAppID + `","recordingId":"` + recordingID + `","tasks":[{"taskType":"transcode-ffmpeg","taskPayload":{"setAsPrimary": true}},{"taskType":"transcribe-voicebase","taskPayload":{"priority": "low"` + termsPayload + `}},{"taskType":"insert-into-index"}]}`
	//fmt.Printf("body=%s", bodyObj)

	// Create Job
	req, err = http.NewRequest("POST", "https://api.veritone.com/v1/job", bytes.NewReader([]byte(bodyObj)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+cfgToken)
	resp, err = http.DefaultClient.Do(req)
	jsonObj, err = ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	fmt.Printf("json=%s", jsonObj)

	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	parser, err = gojq.NewStringQuery(string(jsonObj))
	jobidX, err := parser.Query("jobId")
	jobid := jobidX.(string)

	if err != nil {
		appendError(filename + "~" + err.Error() + "~" + time.Now().Format("2006-01-02 15:04:05"))
		fmt.Println(err)
		return ""
	}

	res := recordingID + "~" + filename +
		"~" + time.Now().Format("2006-01-02 15:04:05") +
		"~" + jobid

	return res

}

func getDuration(filename string) int64 {

	/*
		if cmdOut, err = exec.Command(cmdName, cmdArgs...).Output(); err != nil {
			fmt.Fprintln(os.Stderr, "There was an error running ffprobe duration command: ", err)
			os.Exit(1)
		}
	*/
	cmd := exec.Command("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", "in/"+filename)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		fmt.Println(fmt.Sprint(err) + ": " + stderr.String())
		os.Exit(1)
	}

	s := out.String()
	s = strings.Replace(s, "\r", "", -1)
	s = strings.Replace(s, "\n", "", -1)

	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		fmt.Println(err)
		f = 1
	}

	i := int64(math.Trunc(f))

	fmt.Println("Duration = ", i)
	return i
}

// Run several concurrent instances of workers to receive
// work on the jobs channel and send the corresponding results
func worker(id int, jobs <-chan string, results chan<- string) {
	for ScanLine := range jobs {
		fmt.Println("worker", id, "processing job", ScanLine)
		res := submitFile(ScanLine)
		results <- res
	}
}


/*
expect via environment variables:
TERM_FILE == the file that has the terms -- can be single per line
INPUT_DIR == directory contains the recordings
OUTPUT_DIR== where to write the output

This will start jobs that starts the speechmatics and voicebase with terms

Requires ffprobe

 */
 func main () {
	 app.Action = appRun
	 app.Run(os.Args)
}
func appRun() {
	defer closer.Close()
	closer.Bind(func() {
		log.Println("Finished!")
	})

	// In order to use our pool of workers we need to send
	// them work and collect their results. We make 2 channels for this.
	jobs := make(chan string, 100000)
	results := make(chan string, 100000)

	// This starts up X workers, initially blocked
	// because there are no jobs yet.
	for w := 1; w <= 10; w++ {
		go worker(w, jobs, results)
	}

	file, err := os.Open("mysend_in.txt")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	count := 0
	scanner := bufio.NewScanner(file)

	// Here we send work to the jobs channel
	for scanner.Scan() {
		fmt.Println(scanner.Text())
		jobs <- scanner.Text()
		count = count + 1
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}

	// close channel to indicate that's all the work we have.
	close(jobs)

	// Number of results must match number of jobs, otherwise app terminates early
	// or app gets stuck waiting and never terminates
	// Finally we collect all the results of the work.
	for a := 1; a <= count; a++ {
		fmt.Println("(" + strconv.Itoa(a) + " start)")
		z := <-results
		fmt.Println("results: " + z)
		fmt.Println("(" + strconv.Itoa(a) + " finish)")
		appendLog(z)
	}
}
