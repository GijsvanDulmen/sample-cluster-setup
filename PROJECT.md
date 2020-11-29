# Assumptions:

- A project with the name "cluster-test-02"
- Configured Cloud DNS

# enable Cloud DNS and add domain
gcloud services enable dns.googleapis.com
gcloud beta dns --project=cluster-test-02 managed-zones create gijsvandulmen-dev --description= --dns-name=gijsvandulmen.dev.

# Note the NS-record for the domain and adjust the mentioned name servers in Google Domains