Filename: `dsspeed.pdf`  
Description: A benchmark comparison of different dataset implementations.  
Author: Andreas Maunz `<andreas@maunz.de>`  
Date: 10/2012

# Request per row

(Old) implementation with one query for data entries **per compound**.

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


# Single Table

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

## 'Row Slicing' Version

Results are sorted by compound, then by feature. The long array is sliced into rows.

    @data_entries = query.execute(@rdf).order_by(:cidx, :fidx).collect { |entry| 
      entry.val.to_s.blank? ? nil : \
      (numeric_features[entry.fidx] ? entry.val.to_s.to_f : entry.val.to_s)
    }.each_slice(@features.size).to_a

Timings:

                     user     system      total        real
    ds reading   3.850000   0.090000   3.940000 (  4.643435)

## 'Fill Table' Version

A modification that avoids lookup operations where possible. Also pre-allocates `@data_entries`.

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


# Dataset Tests

Test runtimes changed as follows:

Test             old     new     
---------------- ------- ------- 
dataset.rb       6.998s  7.406s  
dataset_large.rb 64.230s 25.231s 

Table: Runtimes


## Conclusions

Based on the results I implemented the 'Fill Table' variant.


## Note

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

