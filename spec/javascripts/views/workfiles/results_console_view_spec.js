describe("chorus.views.ResultsConsoleView", function() {
    beforeEach(function() {
        this.model = fixtures.task({
            checkId : "foo",
            result : {
                message : "hi there"
            }
        });
        this.view = new chorus.views.ResultsConsole({model: this.model});
    })

    describe("#render", function() {
        beforeEach(function() {
            this.view.render();
        })

        it("displays the result message", function() {
            expect(this.view.$(".right")).not.toHaveClass("executing");
            expect(this.view.$(".message").text().trim()).toBe("hi there")
        })

        it("hides the minimize and maximize links", function() {
            expect(this.view.$("a.minimize")).toHaveClass('hidden')
            expect(this.view.$("a.maximize")).toHaveClass('hidden')
        })
    })

    describe("event handling", function() {
        beforeEach(function() {
            this.view.render();
        })

        describe("file:executionStarted", function() {
            beforeEach(function() {
                spyOn(_, "delay").andCallThrough();
                spyOn(window, "clearTimeout");

                this.view.trigger("file:executionStarted")
            })

            it("sets the executing class", function() {
                expect(this.view.$(".right")).toHaveClass("executing");
            })

            it("sets a delay to start a spinner", function() {
                expect(_.delay).toHaveBeenCalledWith(jasmine.any(Function), 250);
            })

            it("saves the spinner timer id", function() {
                expect(this.view.spinnerTimer).toBeDefined();
            })

            it("starts tracking execution time", function() {
                expect(_.delay).toHaveBeenCalledWith(jasmine.any(Function), 1000);
            })

            describe("cancelling the execution", function() {
                context("when the spinner has not yet been started", function() {
                    beforeEach(function() {
                        this.view.$(".cancel").click();
                    })

                    it("cancels the execution", function() {
                        var update = this.server.lastUpdate();
                        expect(update).toBeDefined();
                        expect(update.requestBody).toContain("action=cancel")
                    })

                    itRemovesExecutionUI(true);
                })

                context("when the spinner has been started", function() {
                    beforeEach(function() {
                        delete this.view.spinnerTimer;
                        delete this.view.elapsedTimer;
                        this.view.$(".cancel").click();
                    })

                    it("cancels the execution", function() {
                        var update = this.server.lastUpdate();
                        expect(update).toBeDefined();
                        expect(update.requestBody).toContain("action=cancel")
                    })

                    itRemovesExecutionUI(false);
                })
            })

            describe("when the execution is completed", function() {
                context("when the spinner has not yet been started", function() {
                    beforeEach(function() {
                        this.task = fixtures.taskWithResult();
                        this.view.trigger("file:executionCompleted", this.task);
                    })

                    itRemovesExecutionUI(true);
                    itShowsExecutionResults();
                });

                context("when the spinner has been started", function() {
                    beforeEach(function() {
                        delete this.view.spinnerTimer;
                        delete this.view.elapsedTimer;
                        this.task = fixtures.taskWithResult();
                        this.view.trigger("file:executionCompleted", this.task);
                    })

                    itRemovesExecutionUI(false);
                    itShowsExecutionResults();
                })
            })

            function itRemovesExecutionUI(shouldCancelTimers) {
                it("removes the executing class", function() {
                    expect(this.view.$(".right")).not.toHaveClass("executing");
                })

                it("stops the spinner", function() {
                    expect(this.view.$(".loading").isLoading()).toBeFalsy();
                })

                if (shouldCancelTimers) {
                    it("cancels the spinner and elapsed time timers", function() {
                        expect(window.clearTimeout.callCount).toBe(2);
                    })
                } else {
                    it("does not cancel the spinner delay", function() {
                        expect(window.clearTimeout).not.toHaveBeenCalled();
                    })
                }

                it("clears timer ids", function() {
                    expect(this.view.spinnerTimer).toBeUndefined();
                    expect(this.view.elapsedTimer).toBeUndefined();
                })
            }

            function itShowsExecutionResults() {
                it("renders a task data table with the given task", function() {
                    expect(this.view.dataTable).toBeA(chorus.views.TaskDataTable);
                    expect(this.view.dataTable.model).toBe(this.task);
                    expect($(this.view.el)).toContain(this.view.dataTable.el);
                });

                it("changes the state of the result table to 'minimized'", function() {
                    expect(this.view.$('.result_table')).not.toHaveClass("collapsed");
                    expect(this.view.$('.result_table')).toHaveClass("minimized");
                    expect(this.view.$('.result_table')).not.toHaveClass("maximized");
                });

                it("renders the maximize link", function() {
                    expect(this.view.$("a.maximize")).not.toHaveClass("hidden");
                    expect(this.view.$("a.minimize")).toHaveClass("hidden");
                });

                describe("clicking the maximize link", function() {
                    beforeEach(function() {
                        this.view.$("a.maximize").click();
                    });

                    it("hides the maximize link and shows the minimize link", function() {
                        expect(this.view.$("a.maximize")).toHaveClass("hidden");
                        expect(this.view.$("a.minimize")).not.toHaveClass("hidden");
                    });

                    it("changes the state of the result table to 'minimized'", function() {
                        expect(this.view.$('.result_table')).not.toHaveClass("collapsed");
                        expect(this.view.$('.result_table')).not.toHaveClass("minimized");
                        expect(this.view.$('.result_table')).toHaveClass("maximized");
                    });

                    xit("sets .data_table height to use the full viewport", function() {

                    });

                    describe("clicking the minimize link", function() {
                        beforeEach(function() {
                            this.view.$("a.minimize").click();
                        });

                        it("hides the minimize link and shows the maximize link", function() {
                            expect(this.view.$("a.minimize")).toHaveClass("hidden");
                            expect(this.view.$("a.maximize")).not.toHaveClass("hidden");
                        });

                        it("changes the state of the result table to 'minimized'", function() {
                            expect(this.view.$('.result_table')).not.toHaveClass("collapsed");
                            expect(this.view.$('.result_table')).toHaveClass("minimized");
                            expect(this.view.$('.result_table')).not.toHaveClass("maximized");
                        });
                    })
                });
            }
        })
    })

    describe("#startSpinner", function() {
        beforeEach(function() {
            this.view.render();
            this.view.spinnerTimer = 22;
            this.view.startSpinner();
        })

        it("deletes the timer id", function() {
            expect(this.view.spinnerTimer).toBeUndefined();
        })

        it("starts the spinner", function() {
            expect(this.view.$(".loading").isLoading()).toBeTruthy();
        })
    })

    describe("#incrementElapsedTime", function() {
        beforeEach(function() {
            this.view.render();
            this.view.elapsedTimer = 22;
            this.view.elapsedTime = 40;
            spyOn(_, "delay").andCallThrough();
            this.view.incrementElapsedTime();
        })

        it("updates execution time", function() {
            expect(this.view.$(".elapsed_time").text().trim()).toMatchTranslation("results_console_view.elapsed", { sec : 41 })
        })

        it("reschedules itself", function() {
            expect(_.delay).toHaveBeenCalledWith(jasmine.any(Function), 1000);
        })
    })
})
