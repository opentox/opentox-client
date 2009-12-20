module OpenTox
	module Algorithm 

		class Fminer #< OpenTox
			include Owl

			def initialize
				super
				self.uri = File.join(@@config[:services]["opentox-algorithm"],'fminer')
				self.title = "fminer"
				self.source = "http://github.com/amaunz/libfminer"
				self.parameters = {
					"Dataset URI" => { :scope => "mandatory", :value => "dataset_uri" },
					"Feature URI for dependent variable" => { :scope => "mandatory", :value => "feature_uri" }
				}
			end

			def self.create_feature_dataset(params)
				RestClient.post params[:feature_generation_uri], :dataset_uri => params[:dataset_uri], :feature_uri => params[:feature_uri] 
			end
		end

		class Lazar #< OpenTox
			include Owl

			def initialize
				super
				self.uri = File.join(@@config[:services]["opentox-algorithm"],'lazar')
				self.title = "lazar"
				self.source = "http://github.com/helma/opentox-algorithm"
				self.parameters = {
					"Dataset URI" =>
						{ :scope => "mandatory", :value => "dataset_uri" },
					"Feature URI for dependent variable" =>
						{ :scope => "mandatory", :value => "feature_uri" },
					"Feature generation URI" =>
						{ :scope => "mandatory", :value => "feature_generation_uri" }
				}
			end
		end

		class Similarity

			def self.weighted_tanimoto(fp_a,fp_b,p)
				common_features = fp_a & fp_b
				all_features = fp_a + fp_b
				common_p_sum = 0.0
				if common_features.size > 0
					common_features.each{|f| common_p_sum += p[f]}
					all_p_sum = 0.0
					all_features.each{|f| all_p_sum += p[f]}
					common_p_sum/all_p_sum
				else
					0.0
				end
			end

		end

	end
end
