Filename: `dsspeed.pdf`  
Description: A benchmark comparison of different dataset implementations.  
Author: Andreas Maunz `<andreas@maunz.de>`  
Date: 10/2012

Some experiments made on branch `development`, using a VirtualBox VM (2 CPU, 2G of RAM), Debian 6.0.5, 64bit.

# Dataset Creation 

Storing a dataset at the 4store backend.

## Generating and Storing Triples.

Implementation with querying the `/compound` service for compound URIs.

    date
    task=`curl -X POST \
      -F "file=@/home/am/opentox-ruby/opentox-test/test/data/kazius.csv;type=text/csv"  
      http://localhost:8083/dataset 2>/dev/null`
    get_result $task
    date

Timings for uploading the Kazius dataset (>4000 compounds. Repeated three times, median reported):

    Sat Nov  3 11:10:04 CET 2012
    http://localhost:8083/dataset/6a92fbf1-9c46-4c72-a487-365589c1210d
    Sat Nov  3 11:10:41 CET 2012

Uploading takes 37s. This time is consumed by the workflow as follows:

- Compound Triples: 33.236s (89.8 %)
- Value Triples: 1.052s (0.03 %)
- Other Triples: <1s (<0.03 %)
- 4store upload: <3s (<0.1 %)

Based on these results I suggest to avoid querying the compound service.
  


# Dataset Read-In

Populating an `OpenTox::Dataset` object in memory, by reading from the 4store backend.

## Request per row

Implementation with one query for data entries **per compound**.

    @compounds.each_with_index do |compound,i|
      query = RDF::Query.new do
        pattern [:data_entry, RDF::OLO.index, i]
        pattern [:data_entry, RDF::OT.values, :values]
        pattern [:values, RDF::OT.feature, :feature]
        pattern [:feature, RDF::OLO.index, :feature_idx]
        pattern [:values, RDF::OT.value, :value]
      end
      values = query.execute(@rdf).sort_by{|s| s.feature_idx}.collect do |s|
        (numeric_features[s.feature_idx] and s.value.to_s != "") ? \
         s.value.to_s.to_f : s.value.to_s
      end
      @data_entries << values.collect{|v| v == "" ? nil : v}
    end

Timings for reading a BBRC feature dataset (85 compounds, 53 features. Repeated three times, median reported):

                     user     system      total        real
    ds reading   6.640000   0.090000   6.730000 (  7.429505)


## Single Table

Now some optimized versions that retrieve entries all at once. A few variables have been renamed for clarity in the query:

    query = RDF::Query.new do
      # compound index: now a free variable
      pattern [:data_entry, RDF::OLO.index, :cidx] 
      pattern [:data_entry, RDF::OT.values, :vals]
      pattern [:vals, RDF::OT.feature, :f]
      pattern [:f, RDF::OLO.index, :fidx]
      pattern [:vals, RDF::OT.value, :val]
    end

Also `RDF::Query::Solutions#order_by` is used instead of the generic `Enumerable#sort_by`, which may have advantages (not tested seperately).

### 'Row Slicing' Version

Results are sorted by compound, then by feature. The long array is sliced into rows.

    @data_entries = query.execute(@rdf).order_by(:cidx, :fidx).collect { |entry| 
      entry.val.to_s.blank? ? nil : \
      (numeric_features[entry.fidx] ? entry.val.to_s.to_f : entry.val.to_s)
    }.each_slice(@features.size).to_a

Timings:

                     user     system      total        real
    ds reading   3.850000   0.090000   3.940000 (  4.643435)

### 'Fill Table' Version

Modification of 'Row Slicing' that avoids lookup operations where possible. Also pre-allocates `@data_entries`.

    clim=(@compounds.size-1)
    cidx=0
    fidx=0
    num=numeric_features[fidx]
    @data_entries = \
    (Array.new(@compounds.size*@features.size)).each_slice(@features.size).to_a
    # order by feature index as to compute numeric status less frequently
    query.execute(@rdf).order_by(:fidx, :cidx).each { |entry| 
      val = entry.val.to_s
      unless val.blank?
        @data_entries[cidx][fidx] = (num ? val.to_f : val)
      end
      if (cidx < clim)
        cidx+=1
      else
        cidx=0
        fidx+=1
        num=numeric_features[fidx]
      end
    }

Timings:

                     user     system      total        real
    ds reading   3.820000   0.040000   3.860000 (  4.540800)

### 'SPARQL' Version

Modification of 'Fill Table' that loads data entries via SPARQL, not RDF query.

    sparql = "SELECT ?value FROM <#{uri}> WHERE {
      ?data_entry <#{RDF::OLO.index}> ?cidx ;
                  <#{RDF::OT.values}> ?v .
      ?v          <#{RDF::OT.feature}> ?f;
                  <#{RDF::OT.value}> ?value .
      ?f          <#{RDF::OLO.index}> ?fidx.
      } ORDER BY ?fidx ?cidx" 

Timings:

                 user     system      total        real
ds reading   1.690000   0.050000   1.740000 (  2.362236)


## Dataset Tests

Test runtimes changed as follows:

Test             old     'Row Slicing' 'SPARQL'
---------------- ------- ------------- -------- 
dataset.rb       6.998s  7.406s        6.341s
dataset_large.rb 64.230s 25.231s       25.071

Table: Runtimes


### Conclusions

In view of the results I implemented the 'SPARQL' version.


### Note

A further modification that avoids querying compounds separately made runtimes much worse again.
The idea was to get the compound together with each data entry:

    #<RDF::Query::Solution:0x24f41cc(
      {
        :compound=>#<RDF::URI:0x2638c68(http://loca [...]
        :cidx=>#<RDF::Literal::Integer:0x2639190("3 [...]
        :data_entry=>#<RDF::Node:0x2639618(_:b1324f [...]
        :vals=>#<RDF::Node:0x17699d0(_:b32bf4000000 [...]
        :f=>#<RDF::URI:0x1638ed0(http://localhost:8 [...]
        :fidx=>#<RDF::Literal::Integer:0x271c170("0 [...]
        :val=>#<RDF::Literal::Integer:0x176879c("0" [...]
      }
    )>

One would add compounds to `@compounds` only for the first run through column no '1'.

