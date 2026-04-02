import { LightningElement, api } from 'lwc';
import getFieldTotals from '@salesforce/apex/DynamicFieldCounterController.getFieldTotals';

export default class DynamicFieldCounter extends LightningElement {

    @api recordId;
    @api childObject;
    @api parentLookupField;
    @api fieldNames;
    @api filterCondition;

    columns = [];
    data = [];
    showComponent = false;

    connectedCallback(){
        this.loadData();
    }

    loadData(){

        const fields = this.fieldNames.split(',').map(f => f.trim());

        getFieldTotals({
            childObject: this.childObject,
            parentLookupField: this.parentLookupField,
            fieldNames: fields,
            filterCondition: this.filterCondition,
            parentId: this.recordId
        })
        .then(result => {

            const labels = result.labels;
            const totals = result.totals;

            // Check if ALL fields are empty
            let allEmpty = true;

            for(let field of fields){
                if(totals[field] !== null && totals[field] !== undefined){
                    allEmpty = false;
                    break;
                }
            }

            // If all values are empty, stop execution
            if(allEmpty){
                this.showComponent = false;
                return;
            }

            // Otherwise build datatable
            let row = {};
            this.columns = [];

            fields.forEach(field => {

                this.columns.push({
                    label: labels[field],
                    fieldName: field,
                    type: 'number',
                    cellAttributes: {
                        alignment: 'left',
                        class: 'cellPadding'
                    }
                });

                row[field] = totals[field];
            });

            this.data = [row];
            this.showComponent = true;

        })
        .catch(error => {
            console.error(error);
            this.showComponent = false;
        });
    }
}