import json,sys
start,end,gran,country,off=sys.argv[1:6]
print(json.dumps({"timeRange":{"start":start,"end":end,"timeZone":"UTC","granularity":gran},
 "filters":[{"field":"countryOrRegion","operator":"EQUALS","value":country}],
 "sorting":[{"field":"rankInGenre","sortOrder":"ASC"}],
 "pagination":{"offset":int(off),"pageSize":5000}}))
