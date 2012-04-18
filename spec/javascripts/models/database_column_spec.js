describe("chorus.models.DatabaseColumn", function() {
    beforeEach(function() {
        this.model = new chorus.models.DatabaseColumn({name: "Col", typeCategory: "WHOLE_NUMBER", type: 'varbit'});
    });

    describe("#initialize", function() {
        context("when there is not tabularData", function() {
            beforeEach(function() {
                this.model.initialize();
            });

            it("does not blow up", function() {
                expect(this.model.get('name')).toBe('Col');
            });

            it("sets the typeClass property on the model", function() {
                expect(this.model.get("typeClass")).toBe("numeric");
            })
        });

        context("when there is tabularData", function() {
            beforeEach(function() {
                this.tabularData = newFixtures.dataset.sandboxTable({objectName: 'taaab', schemaName: 'partyman'});
                this.model.tabularData = this.tabularData;
                this.model.initialize();
            });

            it("sets instanceId, databaseName, schemaName, parentName, and parentType", function() {
                expect(this.model.get("instanceId")).toBe(this.model.tabularData.get('instance').id);
                expect(this.model.get("databaseName")).toBe(this.model.tabularData.get('databaseName'));
                expect(this.model.get("schemaName")).toBe(this.model.tabularData.get('schemaName'));
                expect(this.model.get("parentName")).toBe(this.model.tabularData.get('objectName'));
                expect(this.model.get("parentType")).toBe(this.model.tabularData.metaType());
            });

            describe("#url", function() {
                it("is correct", function() {
                    this.model.set({
                        instanceId: 5,
                        databaseName: "%foo%",
                        schemaName: "b/a/r",
                        parentName: "a space"
                    });
                    var attr = this.model.attributes;
                    var url = this.model.url();
                    expect(url).toContain("/edc/data/5/database/%25foo%25/schema/b%2Fa%2Fr/"+attr.parentType+"/a%20space/column?");
                    expect(url).toContain("filter=" + attr.name);
                    expect(url).toContain("type=meta");
                });
            });

            describe("#toText", function() {
                context("with lowercase names", function() {
                    beforeEach(function() {
                        this.model.set({name: "col"})
                    })
                    it("formats the string to put into the sql editor", function() {
                        expect(this.model.toText()).toBe('col');
                    })
                })
                context("with uppercase names", function() {
                    beforeEach(function() {
                        this.model.set({name: "Col", schemaName: "PartyMAN", parentName: "TAAAB"});
                    })
                    it("puts quotes around the uppercase names", function() {
                        expect(this.model.toText()).toBe('"Col"');
                    })
                })
            })

            describe("#typeClass", function() {
                var expectedTypeMap = {
                    "WHOLE_NUMBER" : "numeric",
                    "REAL_NUMBER" : "numeric",
                    "STRING" : "string",
                    "LONG_STRING" : "string",
                    "BINARY" : "binary",
                    "BOOLEAN" : "boolean",
                    "DATE" : "date",
                    "TIME" : "time",
                    "DATETIME" : "date_time",
                    "OTHER" : "other"
                }

                _.each(expectedTypeMap, function(str, type) {
                    it("works for " + type, function() {
                        expect(new chorus.models.DatabaseColumn({ typeCategory : type }).get("typeClass")).toBe(str);
                    });
                })
            })

            describe("#quotedName", function() {
                beforeEach(function() {
                    this.model.set({typeCategory: "STRING"});
                });

                it("uses the safePGName helper", function() {
                    expect(this.model.quotedName()).toBe(chorus.Mixins.dbHelpers.safePGName(this.model.get("parentName"), this.model.get("name")));
                });
            });
        });
    });
});
